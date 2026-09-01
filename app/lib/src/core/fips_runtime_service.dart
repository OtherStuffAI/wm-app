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
    this.fipsctlPath = '/usr/local/bin/fipsctl',
    this.attestationPath = '/usr/local/etc/fips/wingman-poc-runtime.json',
    FipsProcessRunner? processRunner,
    bool? isMacOS,
    Future<bool> Function(String path)? fileExists,
    Future<String?> Function(String path)? readTextFile,
  })  : bundledPackagePath = bundledPackagePath ?? defaultBundledPackagePath(),
        _processRunner = processRunner ?? Process.run,
        _isMacOS = isMacOS ?? Platform.isMacOS,
        _fileExists = fileExists ?? ((path) => File(path).exists()),
        _readTextFile = readTextFile ?? _readTextFileFromDisk;

  static const expectedVersion = '0.5.0';
  static const configurationScriptName = 'configure-fips-wingman-poc.sh';

  final String bundledPackagePath;
  final String fipsctlPath;
  final String attestationPath;
  final FipsProcessRunner _processRunner;
  final bool _isMacOS;
  final Future<bool> Function(String path) _fileExists;
  final Future<String?> Function(String path) _readTextFile;
  bool _operationInProgress = false;

  static String defaultBundledPackagePath() {
    final executable = File(Platform.resolvedExecutable);
    final contents = executable.parent.parent;
    final packageName = switch (Abi.current()) {
      Abi.macosArm64 => 'fips-0.5.0-macos-arm64.pkg',
      Abi.macosX64 => 'fips-0.5.0-macos-x86_64.pkg',
      _ => 'fips-0.5.0-macos-unsupported.pkg',
    };
    return '${contents.path}/Resources/FIPS/$packageName';
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

  Future<FipsRuntimeStatus> inspect() async {
    if (_operationInProgress) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.starting,
        detail: 'FIPS installation or repair is in progress.',
      );
    }
    return _inspectRuntime();
  }

  Future<FipsRuntimeStatus> _inspectRuntime() async {
    if (!_isMacOS) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.notBundled,
        detail: 'Bundled FIPS is currently supported only by macOS WMapp.',
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
      final launchd = await _run(
        '/bin/launchctl',
        const ['print', 'system/com.fips.daemon'],
      );
      if (launchd.exitCode == 0) {
        if (_looksLikePermissionDenied(status)) {
          return const FipsRuntimeStatus(
            state: FipsRuntimeState.controlAccessPending,
            detail: 'FIPS is installed and its system daemon is loaded, but '
                'this macOS login session has not refreshed its FIPS control '
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
    if (!_isMacOS || !await _fileExists(bundledPackagePath)) {
      return _inspectRuntime();
    }
    final configurationScriptPath = File(bundledPackagePath)
        .parent
        .uri
        .resolve(configurationScriptName)
        .toFilePath();
    if (!await _fileExists(configurationScriptPath)) {
      return const FipsRuntimeStatus(
        state: FipsRuntimeState.notBundled,
        detail: 'The bundled FIPS configuration helper is missing.',
      );
    }
    _operationInProgress = true;
    try {
      final command = installCommand(bundledPackagePath);
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
      return decoded['schema'] == 1 &&
          decoded['fipsVersion'] == expectedVersion &&
          decoded['rendezvousApp'] == 'wingman-fips-poc-v1' &&
          decoded['nostrShareLocalCandidates'] == true &&
          decoded['lanEnabled'] == true &&
          decoded['lanScope'] == 'wingman-fips-poc-v1' &&
          decoded['tunEnabled'] == true &&
          decoded['dnsEnabled'] == true &&
          decoded['udpAdvertiseOnNostr'] == true &&
          decoded['udpAcceptConnections'] == true &&
          decoded['udpOutboundOnly'] == false;
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
