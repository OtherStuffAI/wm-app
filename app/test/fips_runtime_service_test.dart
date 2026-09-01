import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_app/src/core/fips_runtime_service.dart';

void main() {
  final npub = 'npub1${List.filled(58, 'q').join()}';

  test('constructs an authorization command without shell-interpolating paths',
      () {
    const packagePath = '/Applications/Wingman App.app/Contents/Resources/'
        'FIPS/fips-0.5.0-macos.pkg';
    final command = FipsRuntimeService.installCommand(packagePath);

    expect(command.executable, '/usr/bin/osascript');
    expect(command.arguments.first, '-e');
    expect(command.arguments, contains(packagePath));
    expect(
      command.arguments,
      contains('/Applications/Wingman App.app/Contents/Resources/FIPS/'
          'configure-fips-wingman-poc.sh'),
    );
    expect(command.arguments[1], contains('quoted form of packagePath'));
    expect(
      command.arguments[1],
      contains('quoted form of configurationScriptPath'),
    );
  });

  test('parses a running daemon status without exposing its key', () async {
    final calls = <(String, List<String>)>[];
    final service = FipsRuntimeService(
      bundledPackagePath: '/bundle/fips.pkg',
      fipsctlPath: '/usr/local/bin/fipsctl',
      isMacOS: true,
      fileExists: (_) async => true,
      processRunner: (executable, arguments) async {
        calls.add((executable, arguments));
        if (arguments.contains('--version')) {
          return ProcessResult(1, 0, '0.5.0 (rev test)', '');
        }
        return ProcessResult(
          2,
          0,
          '{"data":{"state":"Running","tun_state":"active",'
              '"persistent":true,"identity":{"npub":"$npub"}}}',
          '',
        );
      },
    );

    final status = await service.inspect();

    expect(status.state, FipsRuntimeState.running);
    expect(status.nodeNpub, npub);
    expect(calls.last.$2, ['show', 'status']);
  });

  test('reports an installed but not-ready launch daemon as starting',
      () async {
    final service = FipsRuntimeService(
      bundledPackagePath: '/bundle/fips.pkg',
      isMacOS: true,
      fileExists: (_) async => true,
      processRunner: (executable, arguments) async {
        if (arguments.contains('--version')) {
          return ProcessResult(1, 0, '0.5.0', '');
        }
        if (executable == '/bin/launchctl') {
          return ProcessResult(3, 0, 'loaded', '');
        }
        return ProcessResult(2, 1, '', 'control socket unavailable');
      },
    );

    final status = await service.inspect();

    expect(status.state, FipsRuntimeState.starting);
  });

  test('allows a WebView attempt while first-login control access is pending',
      () async {
    final service = FipsRuntimeService(
      bundledPackagePath: '/bundle/fips.pkg',
      isMacOS: true,
      fileExists: (_) async => true,
      processRunner: (executable, arguments) async {
        if (arguments.contains('--version')) {
          return ProcessResult(1, 0, '0.5.0', '');
        }
        if (executable == '/bin/launchctl') {
          return ProcessResult(3, 0, 'loaded', '');
        }
        return ProcessResult(2, 1, '', 'connect: Permission denied (EACCES)');
      },
    );

    final status = await service.inspect();

    expect(status.state, FipsRuntimeState.controlAccessPending);
    expect(status.canAttemptAppAccess, isTrue);
    expect(status.isRunning, isFalse);
    expect(
        status.detail, contains('open a FIPS app without the optional probe'));
  });

  test('distinguishes missing bundle, missing install, and old install',
      () async {
    Future<FipsRuntimeStatus> inspectWith({
      required Future<bool> Function(String) exists,
      FipsProcessRunner? runner,
    }) {
      return FipsRuntimeService(
        bundledPackagePath: '/bundle/fips.pkg',
        isMacOS: true,
        fileExists: exists,
        processRunner: runner,
      ).inspect();
    }

    expect(
      (await inspectWith(exists: (_) async => false)).state,
      FipsRuntimeState.notBundled,
    );
    expect(
      (await inspectWith(
        exists: (path) async => path == '/bundle/fips.pkg',
      ))
          .state,
      FipsRuntimeState.notInstalled,
    );
    expect(
      (await inspectWith(
        exists: (_) async => true,
        runner: (_, __) async => ProcessResult(1, 0, '0.4.2', ''),
      ))
          .state,
      FipsRuntimeState.installRequired,
    );
  });

  test('marks non-persistent or inactive-TUN status as degraded', () async {
    final service = FipsRuntimeService(
      bundledPackagePath: '/bundle/fips.pkg',
      isMacOS: true,
      fileExists: (_) async => true,
      processRunner: (_, arguments) async {
        if (arguments.contains('--version')) {
          return ProcessResult(1, 0, '0.5.0', '');
        }
        return ProcessResult(
          2,
          0,
          '{"state":"Running","tun_state":"configured",'
              '"persistent":false}',
          '',
        );
      },
    );

    final status = await service.inspect();

    expect(status.state, FipsRuntimeState.degraded);
    expect(status.detail, contains('persistent identity: false'));
  });

  test('uses the v0.5.0 JSON probe syntax', () async {
    final calls = <(String, List<String>)>[];
    final service = FipsRuntimeService(
      bundledPackagePath: '/bundle/fips.pkg',
      isMacOS: true,
      fileExists: (_) async => true,
      processRunner: (executable, arguments) async {
        calls.add((executable, arguments));
        if (arguments.contains('--version')) {
          return ProcessResult(1, 0, '0.5.0', '');
        }
        if (arguments.length >= 2 && arguments[0] == 'show') {
          return ProcessResult(
            2,
            0,
            '{"state":"Running","tun_state":"active","persistent":true}',
            '',
          );
        }
        return ProcessResult(3, 0, '{"verdict":"ok"}', '');
      },
    );

    final result = await service.probe(npub);

    expect(result.ok, isTrue);
    expect(calls.last.$2, ['probe', npub, '--json', '--timeout', '15']);
  });

  test('redacts private key material from diagnostics', () {
    final nsec = 'nsec1${List.filled(58, 'q').join()}';
    final redacted = FipsRuntimeService.redactSecrets(
      'failed nsec=$nsec private_key=abcdef secret:xyz',
    );

    expect(redacted, isNot(contains(nsec)));
    expect(redacted, isNot(contains('abcdef')));
    expect(redacted, isNot(contains('xyz')));
  });
}
