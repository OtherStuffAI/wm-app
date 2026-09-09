import Foundation
import Security

// macOS host harness: production Rust runtime + production Swift output pump.
// It neither installs a VPN nor measures physical-device battery use.
@main struct PacketSmoke {
    static func decode(_ p: UnsafeMutablePointer<CChar>?) -> [String: Any] {
        guard let p else { fatalError("missing JSON") }
        defer { wm_fips_string_free(p) }
        return try! JSONSerialization.jsonObject(with: Data(String(cString: p).utf8)) as! [String: Any]
    }
    static func query(_ id: UInt16) -> [UInt8] {
        var dns: [UInt8] = [UInt8(id >> 8), UInt8(id & 255),1,0,0,1,0,0,0,0,0,0]
        for label in ["example", "com"] { dns.append(UInt8(label.count)); dns += label.utf8 }
        dns += [0,0,28,0,1]
        var p = [UInt8](repeating: 0, count: 28)
        let length = p.count + dns.count
        p[0]=0x45; p[2]=UInt8(length >> 8); p[3]=UInt8(length & 255); p[9]=17
        p.replaceSubrange(12..<20, with: [10,1,1,2,10,1,1,1])
        p[20]=16; p[21]=146; p[23]=53; p[25]=UInt8(dns.count+8)
        return p + dns
    }
    static func main() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wm-fips-smoke-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = FileManager.default.currentDirectoryPath
        defer { _ = FileManager.default.changeCurrentDirectoryPath(previous); try? FileManager.default.removeItem(at: directory) }
        var key = [UInt8](repeating: 0, count: 32)
        assert(SecRandomCopyBytes(kSecRandomDefault, 32, &key) == errSecSuccess)
        let result = key.withUnsafeBufferPointer { p in directory.path.withCString { decode(wm_fips_start(p.baseAddress, $0)) } }
        key = [UInt8](repeating: 0, count: 32)
        assert(result["state"] as? String == "running")
        let queue = DispatchQueue(label: "fips.host.packets")
        let fd = wm_fips_output_descriptor(); assert(fd >= 0)
        var pump: FipsOutputPump?
        var reads=0, batches=0, packets=0, maxBatch=0, failures=0
        let received = DispatchSemaphore(value: 0)
        queue.sync {
            pump = FipsOutputPump(descriptor: fd, queue: queue, accepts: { true }, read: {
                reads += 1; return wm_fips_output($0, $1)
            }, write: { batch in
                batches += 1; packets += batch.count; maxBatch = max(maxBatch, batch.count)
                for p in batch {
                    assert(p.count > 31 && p[0] >> 4 == 4 && p[31] & 15 == 5) // local REFUSED, no public fallback
                    received.signal()
                }
                return true
            }, failed: { failures += 1 })
        }
        let began = Date()
        Thread.sleep(forTimeInterval: 5)
        queue.sync { assert(reads == 0 && batches == 0 && failures == 0) }
        print("host_idle_seconds=\(Date().timeIntervalSince(began)) output_reads=0 delivery_batches=0 (old timer scheduled ~500 drains)")
        for id in 0..<256 {
            let packet = query(UInt16(id))
            assert(packet.withUnsafeBufferPointer { wm_fips_input($0.baseAddress, $0.count) } == 0)
            assert(received.wait(timeout: .now() + 3) == .success)
        }
        // Hold the production consumer while DNS produces a real burst.
        // This queues no extra dispatch tasks: the source coalesces readiness.
        queue.sync {
            for id in 256..<272 {
                let packet = query(UInt16(id))
                assert(packet.withUnsafeBufferPointer { wm_fips_input($0.baseAddress, $0.count) } == 0)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        for _ in 0..<16 { assert(received.wait(timeout: .now() + 3) == .success) }
        queue.sync { assert(packets == 272 && failures == 0 && maxBatch > 1 && maxBatch <= 32); print("host_active_dns_packets=\(packets) batches=\(batches) maximum_batch=\(maxBatch) output_reads=\(reads)") }
        // Runtime death / shutdown signals EOF and the production pump cancels
        // itself without a callback->stop wait cycle.
        assert(decode(wm_fips_stop())["state"] as? String == "notInstalled")
        for _ in 0..<100 {
            if queue.sync(execute: { failures == 1 }) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        queue.sync { assert(failures == 1); pump?.cancel(); pump = nil }
        for _ in 0..<100 where fcntl(fd, F_GETFD) != -1 { Thread.sleep(forTimeInterval: 0.001) }
        assert(fcntl(fd, F_GETFD) == -1 && errno == EBADF)
        print("host_terminal_eof_failures=1 descriptor_closed=true")
    }
}
