import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_app/src/features/browser/signer_policy.dart';

void main() {
  group('SignerPolicy', () {
    test('normalizes trusted origins and allows matching injection', () {
      final policy = SignerPolicy(
        trustedOrigins: const ['https://flightdeck.example/app'],
      );

      expect(policy.trustedOrigins, ['https://flightdeck.example']);
      expect(policy.canInject('https://flightdeck.example/tasks'), isTrue);
      expect(policy.canInject('https://unknown.example/tasks'), isFalse);
    });

    test('allows NIP-98 only when page and target origins are trusted', () {
      final policy = SignerPolicy(
        trustedOrigins: const [
          'https://flightdeck.example',
          'https://tower.example',
        ],
      );

      final decision = policy.validateNip98(
        pageUrl: 'https://flightdeck.example/app',
        targetUrl: 'https://tower.example/api/v4/flightdeck-pg/service',
        method: 'post',
      );

      expect(decision.allowed, isTrue);
      expect(decision.method, 'POST');
      expect(decision.pageOrigin, 'https://flightdeck.example');
      expect(decision.targetOrigin, 'https://tower.example');
    });

    test('denies untrusted page origins', () {
      final policy = SignerPolicy(
        trustedOrigins: const ['https://tower.example'],
      );

      final decision = policy.validateNip98(
        pageUrl: 'https://evil.example',
        targetUrl: 'https://tower.example/api',
        method: 'GET',
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('untrusted WebView origin'));
    });

    test('denies untrusted target origins', () {
      final policy = SignerPolicy(
        trustedOrigins: const ['https://flightdeck.example'],
      );

      final decision = policy.validateNip98(
        pageUrl: 'https://flightdeck.example',
        targetUrl: 'https://evil.example/api',
        method: 'GET',
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('untrusted NIP-98 target origin'));
    });

    test('denies unsupported target schemes and methods', () {
      final policy = SignerPolicy(
        trustedOrigins: const ['https://flightdeck.example'],
      );

      expect(
        policy
            .validateNip98(
              pageUrl: 'https://flightdeck.example',
              targetUrl: 'file:///tmp/secret',
              method: 'GET',
            )
            .allowed,
        isFalse,
      );
      expect(
        policy
            .validateNip98(
              pageUrl: 'https://flightdeck.example',
              targetUrl: 'https://flightdeck.example/api',
              method: 'TRACE',
            )
            .allowed,
        isFalse,
      );
    });

    test('denies oversized request bodies', () {
      final policy = SignerPolicy(
        trustedOrigins: const ['https://flightdeck.example'],
        maxBodyBytes: 4,
      );

      final decision = policy.validateNip98(
        pageUrl: 'https://flightdeck.example',
        targetUrl: 'https://flightdeck.example/api',
        method: 'POST',
        body: '12345',
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('too large'));
    });
  });
}
