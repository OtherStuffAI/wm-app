import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef FipsProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

enum FipsRuntimeState {
  notBundled,
  notInstalled,
  installRequired,
  starting,
  controlAccessPending,
  running,
  degraded,
  failed,
}

class FipsRuntimeStatus {
  const FipsRuntimeStatus({
    required this.state,
    required this.detail,
    this.nodeNpub,
  });

  final FipsRuntimeState state;
  final String detail;
  final String? nodeNpub;

  bool get isRunning => state == FipsRuntimeState.running;
  bool get canAttemptAppAccess =>
      state == FipsRuntimeState.running ||
      state == FipsRuntimeState.controlAccessPending;
}

class FipsProbeResult {
  const FipsProbeResult({
    required this.ok,
    required this.detail,
  });

  final bool ok;
  final String detail;
}

class FipsCommand {
  const FipsCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class FipsRuntimeService {
  FipsRuntimeService({
    String? bundledPackagePath,
    String? fipsctlPath,
    String? attestationPath,
    FipsProcessRunner? processRunner,
    bool? isMacOS,
    bool? isLinux,
    Future<bool> Function(String path)? fileExists,
    Future<String?> Function(String path)? readTextFile,
  })  : bundledPackagePath = bundledPackagePath ??
            defaultBundledPackagePath(isMacOS: isMacOS, isLinux: isLinux),
        fipsctlPath = fipsctlPath ?? '/usr/local/bin/fipsctl',
        attestationPath = attestationPath ??
            defaultAttestationPath(isMacOS: isMacOS, isLinux: isLinux),
        _processRunner = processRunner ?? Process.run,
        _isMacOS = isMacOS ?? (isLinux == true ? false : Platform.isMacOS),
        _isLinux = isLinux ?? (isMacOS == true ? false : Platform.isLinux),
        _fileExists = fileExists ?? ((path) => File(path).exists()),
        _readTextFile = readTextFile ?? _readTextFileFromDisk;

  static const expectedVersion = '0.5.0';
  static const configurationScriptName = 'configure-fips-wingman-poc.sh';
  static const linuxConfigurationScriptName = 'configure_fips_wingman_linux.sh';
  static const linuxInstallScriptName = 'install_fips_wingman_linux.sh';
  static const bootstrapPeerNpub =
      'npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98';
  static const bootstrapPeerAddress = '217.77.8.91:2121';

  final String bundledPackagePath;
  final String fipsctlPath;
  final String attestationPath;
  final FipsProcessRunner _processRunner;
  final bool _isMacOS;
  final bool _isLinux;
  final Future<bool> Function(String path) _fileExists;
  final Future<String?> Function(String path) _readTextFile;
  bool _operationInProgress = false;
  Future<FipsRuntimeStatus>? _ensureReadyOperation;

  static String defaultBundledPackagePath({bool? isMacOS, bool? isLinux}) {
    final resolvedIsLinux =
        isLinux ?? (isMacOS == true ? false : Platform.isLinux);
    if (resolvedIsLinux) {
      return '${File(Platform.resolvedExecutable).parent.path}/data/fips/install.sh';
    }
    final executable = File(Platform.resolvedExecutable);
    final contents = executable.parent.parent;
    final packageName = switch (Abi.current()) {
      Abi.macosArm64 => 'fips-0.5.0-macos-arm64.pkg',
      Abi.macosX64 => 'fips-0.5.0-macos-x86_64.pkg',
      _ => 'fips-0.5.0-macos-unsupported.pkg',
    };
    return '${contents.path}/Resources/FIPS/$packageName';
  }

  static String defaultAttestationPath({bool? isMacOS, bool? isLinux}) {
    final resolvedIsLinux =
        isLinux ?? (isMacOS == true ? false : Platform.isLinux);
    return resolvedIsLinux
        ? '/etc/fips/wingman-poc-runtime.json'
        : '/usr/local/etc/fips/wingman-poc-runtime.json';
  }

  static FipsCommand installCommand(String packagePath) {
    final configurationScriptPath = File(packagePath)
        .parent
        .uri
        .resolve(configurationScriptName)
        .toFilePath();
    const script = '''
on run argv
  set packagePath to item 1 of argv
  set configurationScriptPath to item 2 of argv
  do shell script ("/usr/sbin/installer -pkg " & quoted form of packagePath & " -target / && /bin/sh " & quoted form of configurationScriptPath) with administrator privileges
end run
''';
    return FipsCommand(
      '/usr/bin/osascript',
      ['-e', script, packagePath, configurationScriptPath],
    );
  }

  static FipsCommand linuxInstallCommand(String upstreamInstallPath) {
    final activationPath = File(upstreamInstallPath)
        .parent
        .uri
        .resolve(linuxInstallScriptName)
        .toFilePath();
    return FipsCommand('/usr/bin/pkexec', ['/bin/sh', activationPath]);
  }

  String get authorizationDescription => _isLinux
      ? 'Linux will request administrator authorization. The pinned FIPS '
          'systemd bundle installs the mesh daemon, TUN support, and the '
          '.fips resolver. Existing FIPS configuration and machine identity '
          'are preserved.'
      : 'macOS will request administrator authorization. The pinned FIPS '
          'system package installs a launch daemon, TUN support, and the '
          '.fips resolver. Existing FIPS configuration and machine identity '
          'are preserved.';

  String get authorizationWaitingMessage => _isLinux
      ? 'Waiting for Linux administrator authorization…'
      : 'Waiting for macOS authorization…';

  Future<FipsRuntimeStatus> inspect() async {
    if (_operationInProgress) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.starting,
        detail: 'FIPS installation or repair is in progress.',
      );
    }
    return _inspectRuntime();
  }

  Future<FipsRuntimeStatus> ensureReadyForAppAccess() {
    final activeOperation = _ensureReadyOperation;
    if (activeOperation != null) return activeOperation;

    final operation = _ensureReadyForAppAccess();
    late final Future<FipsRuntimeStatus> trackedOperation;
    trackedOperation = operation.whenComplete(() {
      if (identical(_ensureReadyOperation, trackedOperation)) {
        _ensureReadyOperation = null;
      }
    });
    _ensureReadyOperation = trackedOperation;
    return trackedOperation;
  }

  Future<FipsRuntimeStatus> _ensureReadyForAppAccess() async {
    var status = await inspect();

    if (!status.canAttemptAppAccess) {
      final canActivateBundledRuntime = switch (status.state) {
        FipsRuntimeState.notInstalled ||
        FipsRuntimeState.installRequired ||
        FipsRuntimeState.degraded ||
        FipsRuntimeState.failed =>
          true,
        _ => false,
      };
      if (!canActivateBundledRuntime) return status;
      status = await installOrRepair();
    }
    if (!status.canAttemptAppAccess) return status;
    return _ensureBootstrapConnected(status);
  }

  Future<FipsRuntimeStatus> _ensureBootstrapConnected(
    FipsRuntimeStatus readyStatus,
  ) async {
    if (readyStatus.state == FipsRuntimeState.controlAccessPending) {
      return readyStatus;
    }

    for (var attempt = 0; attempt < 12; attempt += 1) {
      final peers = await _run(fipsctlPath, const ['show', 'peers']);
      if (peers.exitCode == 0 && _bootstrapIsConnected(peers.stdout)) {
        return readyStatus;
      }
      if (attempt == 0) {
        final connect = await _run(fipsctlPath, const [
          'connect',
          bootstrapPeerNpub,
          bootstrapPeerAddress,
          'udp',
        ]);
        if (connect.exitCode != 0) {
          return FipsRuntimeStatus(
            state: FipsRuntimeState.degraded,
            detail: 'FIPS is running, but its authenticated bootstrap link '
                'could not start: ${_resultDetail(connect)}',
            nodeNpub: readyStatus.nodeNpub,
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return FipsRuntimeStatus(
      state: FipsRuntimeState.degraded,
      detail: 'FIPS is running, but the authenticated bootstrap peer did not '
          'connect. Check that outbound UDP port 2121 is allowed.',
      nodeNpub: readyStatus.nodeNpub,
    );
  }

  static bool _bootstrapIsConnected(Object output) {
    try {
      final decoded = jsonDecode(output.toString());
      final data = decoded is Map<String, dynamic> &&
              decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded;
      if (data is! Map<String, dynamic> || data['peers'] is! List) {
        return false;
      }
      return (data['peers'] as List).any((peer) =>
          peer is Map<String, dynamic> &&
          peer['npub'] == bootstrapPeerNpub &&
          peer['connectivity']?.toString().toLowerCase() == 'connected');
    } catch (_) {
      return false;
    }
  }

  Future<FipsRuntimeStatus> _inspectRuntime() async {
    if (!_isMacOS && !_isLinux) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.notBundled,
        detail: 'Bundled desktop FIPS is supported on macOS and Linux WMapp.',
      );
    }
    if (!await _fileExists(bundledPackagePath)) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.notBundled,
        detail: 'The pinned FIPS installer is missing from this app bundle.',
      );
    }
    if (!await _fileExists(fipsctlPath)) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.notInstalled,
        detail: 'Bundled FIPS is ready to enable. It will activate '
            'automatically when you open a FIPS app.',
      );
    }

    final version = await _run(fipsctlPath, const ['--version']);
    if (version.exitCode != 0) {
      return FipsRuntimeStatus(
        state: FipsRuntimeState.failed,
        detail: 'Could not inspect fipsctl: ${_resultDetail(version)}',
      );
    }
    if (!version.stdout.toString().contains(expectedVersion)) {
      return FipsRuntimeStatus(
        state: FipsRuntimeState.installRequired,
        detail: 'FIPS $expectedVersion is required; installed: '
            '${redactSecrets(version.stdout.toString().trim())}.',
      );
    }

    if (!await _hasCompatibleWingmanAttestation()) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.installRequired,
        detail: 'FIPS is installed, but its bundled Wingman mesh setup is '
            'missing or outdated. Opening a FIPS app will repair it while '
            'preserving this machine identity.',
      );
    }

    final status = await _run(fipsctlPath, const ['show', 'status']);
    if (status.exitCode != 0) {
      final service = _isLinux
          ? await _run(
              '/usr/bin/systemctl', const ['is-active', 'fips.service'])
          : await _run(
              '/bin/launchctl',
              const ['print', 'system/com.fips.daemon'],
            );
      if (service.exitCode == 0) {
        if (_looksLikePermissionDenied(status)) {
          return FipsRuntimeStatus(
            state: FipsRuntimeState.controlAccessPending,
            detail: 'FIPS is installed and its system service is loaded, but '
                'this ${_isLinux ? 'Linux' : 'macOS'} login session has not refreshed its FIPS control '
                'permission yet. You can open a FIPS app without the optional '
                'probe now; log out and back in to enable diagnostics.',
          );
        }
        return FipsRuntimeStatus(
          state: FipsRuntimeState.starting,
          detail:
              'The FIPS daemon is loaded but its control socket is not ready: '
              '${_resultDetail(status)}',
        );
      }
      return FipsRuntimeStatus(
        state: FipsRuntimeState.failed,
        detail: 'FIPS is installed but the daemon is unavailable: '
            '${_resultDetail(status)}',
      );
    }

    try {
      final decoded = jsonDecode(status.stdout.toString());
      final data = decoded is Map<String, dynamic> &&
              decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded as Map<String, dynamic>;
      final state = data['state']?.toString().toLowerCase() ?? '';
      final tunState = data['tun_state']?.toString().toLowerCase() ?? '';
      final persistent = data['persistent'] == true;
      final nodeNpub =
          _findString(data, const ['npub', 'node_npub', 'identity']);
      if (state == 'failed') {
        return FipsRuntimeStatus(
          state: FipsRuntimeState.failed,
          detail: 'The FIPS daemon reports a failed state.',
          nodeNpub: nodeNpub,
        );
      }
      if (state == 'created' || state == 'starting') {
        return FipsRuntimeStatus(
          state: FipsRuntimeState.starting,
          detail: 'The FIPS daemon is starting.',
          nodeNpub: nodeNpub,
        );
      }
      if (state != 'running' || tunState != 'active' || !persistent) {
        return FipsRuntimeStatus(
          state: FipsRuntimeState.degraded,
          detail: 'FIPS is reachable but not ready for stable WApp access '
              '(state: ${state.isEmpty ? 'unknown' : state}, '
              'TUN: ${tunState.isEmpty ? 'unknown' : tunState}, '
              'persistent identity: $persistent).',
          nodeNpub: nodeNpub,
        );
      }
      return FipsRuntimeStatus(
        state: FipsRuntimeState.running,
        detail: 'FIPS $expectedVersion is running.',
        nodeNpub: nodeNpub,
      );
    } catch (error) {
      return FipsRuntimeStatus(
        state: FipsRuntimeState.degraded,
        detail: 'FIPS responded, but its status was not understood: '
            '${redactSecrets(error.toString())}',
      );
    }
  }

  Future<FipsRuntimeStatus> installOrRepair() async {
    if ((!_isMacOS && !_isLinux) || !await _fileExists(bundledPackagePath)) {
      return _inspectRuntime();
    }
    final helperName =
        _isLinux ? linuxInstallScriptName : configurationScriptName;
    final helperPath =
        File(bundledPackagePath).parent.uri.resolve(helperName).toFilePath();
    if (!await _fileExists(helperPath)) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.notBundled,
        detail: 'The bundled FIPS activation helper is missing.',
      );
    }
    _operationInProgress = true;
    try {
      final command = _isLinux
          ? linuxInstallCommand(bundledPackagePath)
          : installCommand(bundledPackagePath);
      final result = await _run(command.executable, command.arguments);
      if (result.exitCode != 0) {
        return FipsRuntimeStatus(
          state: FipsRuntimeState.failed,
          detail: 'FIPS installation was cancelled or failed: '
              '${_resultDetail(result)}',
        );
      }
      for (var attempt = 0; attempt < 10; attempt += 1) {
        final status = await _inspectRuntime();
        if (status.state != FipsRuntimeState.starting) return status;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.starting,
        detail: 'FIPS was installed and is still starting.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<FipsProbeResult> probe(String npub) async {
    if (!RegExp(r'^npub1[023456789acdefghjklmnpqrstuvwxyz]{58}$')
        .hasMatch(npub)) {
      return const FipsProbeResult(
          ok: false, detail: 'Invalid FIPS node npub.');
    }
    final status = await inspect();
    if (!status.isRunning) {
      return FipsProbeResult(ok: false, detail: status.detail);
    }
    final result = await _run(
      fipsctlPath,
      ['probe', npub, '--json', '--timeout', '15'],
    );
    return FipsProbeResult(
      ok: result.exitCode == 0,
      detail: _resultDetail(result),
    );
  }

  Future<ProcessResult> _run(String executable, List<String> arguments) async {
    try {
      return await _processRunner(executable, arguments);
    } catch (error) {
      return ProcessResult(0, 127, '', redactSecrets(error.toString()));
    }
  }

  Future<bool> _hasCompatibleWingmanAttestation() async {
    final raw = await _readTextFile(attestationPath);
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      return decoded['schema'] == 2 &&
          decoded['fipsVersion'] == expectedVersion &&
          decoded['rendezvousApp'] == 'wingman-fips-poc-v1' &&
          decoded['nostrShareLocalCandidates'] == true &&
          decoded['lanEnabled'] == true &&
          decoded['lanScope'] == 'wingman-fips-poc-v1' &&
          decoded['tunEnabled'] == true &&
          decoded['dnsEnabled'] == true &&
          decoded['udpAdvertiseOnNostr'] == true &&
          decoded['udpAcceptConnections'] == true &&
          decoded['udpOutboundOnly'] == false &&
          decoded['bootstrapPeerNpub'] == bootstrapPeerNpub &&
          decoded['bootstrapPeerAddress'] == bootstrapPeerAddress;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _readTextFileFromDisk(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }

  static String _resultDetail(ProcessResult result) {
    final stderr = redactSecrets(result.stderr.toString().trim());
    final stdout = redactSecrets(result.stdout.toString().trim());
    if (stderr.isNotEmpty) return stderr;
    if (stdout.isNotEmpty) return stdout;
    return 'command exited ${result.exitCode}';
  }

  static bool _looksLikePermissionDenied(ProcessResult result) {
    final detail = '${result.stderr}\n${result.stdout}'.toLowerCase();
    return detail.contains('permission denied') ||
        detail.contains('operation not permitted') ||
        detail.contains('eacces');
  }

  static String? _findString(Map<String, dynamic> value, List<String> keys) {
    for (final key in keys) {
      final found = value[key]?.toString().trim();
      if (found != null && found.startsWith('npub1')) return found;
    }
    for (final child in value.values) {
      if (child is Map<String, dynamic>) {
        final found = _findString(child, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String redactSecrets(String value) {
    return value
        .replaceAll(
          RegExp(r'nsec1[023456789acdefghjklmnpqrstuvwxyz]+'),
          '[redacted-nsec]',
        )
        .replaceAll(
          RegExp(
            r'("?(?:private[_ -]?key|secret|nsec)"?\s*[:=]\s*)[^\s,}]+',
            caseSensitive: false,
          ),
          r'$1[redacted]',
        );
  }
}
