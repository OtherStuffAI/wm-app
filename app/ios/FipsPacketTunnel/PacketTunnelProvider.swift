import NetworkExtension
import Security
import Network

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let worker = DispatchQueue(label: "com.wingman.fips.packet", qos: .userInitiated)
    private var generation = 0
    private var active = false
    private var readOutstanding = false
    private var timer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private var pathSignature: String?
    private var healthTicks = 0
    private var startCompletion: ((Error?) -> Void)?

    private func decode(_ pointer: UnsafeMutablePointer<CChar>?) -> [String: Any] {
        guard let pointer else { return ["state": "failed"] }
        defer { wm_fips_string_free(pointer) }
        return (try? JSONSerialization.jsonObject(with: Data(String(cString: pointer).utf8))) as? [String: Any] ?? ["state": "failed"]
    }
    private func error(_ code: Int) -> NSError {
        NSError(domain: "com.wingman.fips", code: code, userInfo: [NSLocalizedDescriptionKey: "FIPS VPN could not start. Open Setup to retry."])
    }
    // No access group: only the extension can retrieve this node key. It is
    // unrelated to WMAPP's user signer and remains available after screen lock.
    private func nodeKey() throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.wingman.fips.node.v1", kSecAttrAccount as String: "node"]
        var lookup = query
        lookup[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let bytes = item as? Data, bytes.count == 32 { return bytes }
        guard status == errSecItemNotFound else { throw error(10) }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw error(11) }
        var insert = query
        insert[kSecValueData as String] = bytes
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { bytes.resetBytes(in: 0..<bytes.count); throw error(12) }
        return bytes
    }
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        worker.async {
            guard !self.active, self.startCompletion == nil else { completionHandler(self.error(1)); return }
            self.generation += 1
            let generation = self.generation
            self.startCompletion = completionHandler
            do {
                var key = try self.nodeKey()
                defer { key.resetBytes(in: 0..<key.count) }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fips", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                let status = key.withUnsafeBytes { key in
                    directory.path.withCString { self.decode(wm_fips_start(key.bindMemory(to: UInt8.self).baseAddress!, $0)) }
                }
                guard status["state"] as? String == "running", let ipv6 = status["ipv6"] as? String else { throw self.error(2) }
                let settings = FipsTunnelSettings.make(ipv6: ipv6)
                self.setTunnelNetworkSettings(settings) { error in
                    self.worker.async {
                        guard self.generation == generation else { return }
                        if let error { self.finishStart(error); return }
                        self.active = true
                        self.readPackets(generation)
                        self.startDrain(generation)
                        self.monitorPath()
                        self.finishStart(nil)
                    }
                }
                self.worker.asyncAfter(deadline: .now() + 20) {
                    guard self.generation == generation, self.startCompletion != nil else { return }
                    self.finishStart(self.error(3))
                }
            } catch { self.finishStart(error) }
        }
    }
    private func finishStart(_ error: Error?) {
        if error != nil {
            generation += 1; active = false
            timer?.cancel(); timer = nil
            _ = decode(wm_fips_stop())
        }
        let completion = startCompletion; startCompletion = nil
        completion?(error)
    }
    private func readPackets(_ generation: Int) {
        guard active, self.generation == generation, !readOutstanding else { return }
        readOutstanding = true
        packetFlow.readPackets { packets, protocols in
            self.worker.async {
                self.readOutstanding = false
                guard self.active else { return }
                guard self.generation == generation else { self.readPackets(self.generation); return }
                // One outstanding read only; no per-packet async task backlog.
                for (packet, proto) in zip(packets.prefix(64), protocols.prefix(64)) where
                    (proto.int32Value == AF_INET || proto.int32Value == AF_INET6) && packet.count <= 1280 {
                    packet.withUnsafeBytes { _ = wm_fips_input($0.bindMemory(to: UInt8.self).baseAddress, packet.count) }
                }
                self.readPackets(generation)
            }
        }
    }
    private func startDrain(_ generation: Int) {
        let timer = DispatchSource.makeTimerSource(queue: worker)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self, self.active, self.generation == generation else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            var packets: [Data] = []; var protocols: [NSNumber] = []
            self.healthTicks += 1
            if self.healthTicks % 100 == 0, self.decode(wm_fips_status())["state"] as? String != "running" {
                self.cancelTunnelWithError(self.error(5)); return
            }
            for _ in 0..<64 {
                let count = wm_fips_output(&buffer, buffer.count)
                if count <= 0 { break }
                packets.append(Data(buffer.prefix(Int(count))))
                protocols.append(NSNumber(value: buffer[0] >> 4 == 6 ? AF_INET6 : AF_INET))
            }
            if !packets.isEmpty { _ = self.packetFlow.writePackets(packets, withProtocols: protocols) }
        }
        self.timer = timer; timer.resume()
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        worker.async {
            self.generation += 1; self.active = false
            self.timer?.cancel(); self.timer = nil
            self.pathMonitor?.cancel(); self.pathMonitor = nil; self.pathSignature = nil
            let pending = self.startCompletion; self.startCompletion = nil
            _ = self.decode(wm_fips_stop())
            pending?(self.error(4))
            completionHandler()
        }
    }
    private func monitorPath() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, self.active else { return }
            let signature = "\(path.status)-\(path.usesInterfaceType(.wifi))-\(path.usesInterfaceType(.cellular))-\(path.usesInterfaceType(.wiredEthernet))"
            let previous = self.pathSignature
            self.pathSignature = signature
            guard previous != nil, previous != signature else { return }
            self.reasserting = true
            guard path.status == .satisfied else { return }
            // Recreate UDP and peer state on interface changes, keeping the
            // Keychain node identity. Debounce repeated path notifications.
            let generation = self.generation
            self.worker.asyncAfter(deadline: .now() + 1) {
                guard self.active, self.generation == generation, self.pathSignature == signature else { return }
                self.generation += 1; self.active = false
                self.timer?.cancel(); self.timer = nil
                _ = self.decode(wm_fips_stop())
                self.startTunnel(options: nil) { error in
                    self.worker.async {
                        self.reasserting = false
                        if let error { self.cancelTunnelWithError(error) }
                    }
                }
            }
        }
        pathMonitor = monitor
        monitor.start(queue: worker)
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Commands are fixed and contain no key/configuration access.
        worker.async {
            guard messageData.count <= 64 else { completionHandler?(nil); return }
            let command = String(data: messageData, encoding: .utf8)
            let result: [String: Any]
            switch command {
            case "inspect": result = self.decode(wm_fips_status())
            case "peerStatus": result = self.decode(wm_fips_peers())
            default: result = ["state": "failed", "detail": "Unsupported FIPS diagnostic command."]
            }
            completionHandler?(try? JSONSerialization.data(withJSONObject: result))
        }
    }
}
