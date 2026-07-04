import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_app/src/features/browser/signer_store.dart';

void main() {
  group('SignerStore', () {
    test('remembers and revokes NIP-98 origin approvals', () async {
      final store = SignerStore(backend: MemorySignerStoreBackend());
      final approval = SignerApproval(
        pageOrigin: 'https://flightdeck.example',
        targetOrigin: 'https://tower.example',
        deviceNpub: 'npub1device',
        createdAt: DateTime.utc(2026, 7, 4),
      );

      expect(
        await store.hasApproval(
          pageOrigin: approval.pageOrigin,
          targetOrigin: approval.targetOrigin,
          deviceNpub: approval.deviceNpub,
        ),
        isFalse,
      );

      await store.rememberApproval(approval);

      expect(await store.listApprovals(), hasLength(1));
      expect(
        await store.hasApproval(
          pageOrigin: approval.pageOrigin,
          targetOrigin: approval.targetOrigin,
          deviceNpub: approval.deviceNpub,
        ),
        isTrue,
      );

      await store.revokeApproval(approval.key);

      expect(await store.listApprovals(), isEmpty);
    });

    test('stores bounded newest-first audit entries', () async {
      final store = SignerStore(
        backend: MemorySignerStoreBackend(),
        maxAuditEntries: 2,
      );

      await store.appendAudit(
        SignerAuditEntry.create(
          pageOrigin: 'https://flightdeck.example',
          targetOrigin: 'https://tower.example',
          targetUrl: 'https://tower.example/a',
          method: 'GET',
          deviceNpub: 'npub1device',
          allowed: true,
          outcome: 'signed',
        ),
      );
      await store.appendAudit(
        SignerAuditEntry.create(
          pageOrigin: 'https://flightdeck.example',
          targetOrigin: 'https://tower.example',
          targetUrl: 'https://tower.example/b',
          method: 'POST',
          deviceNpub: 'npub1device',
          allowed: false,
          outcome: 'user_denied',
          reason: 'denied by user',
        ),
      );
      await store.appendAudit(
        SignerAuditEntry.create(
          pageOrigin: 'https://flightdeck.example',
          targetOrigin: 'https://tower.example',
          targetUrl: 'https://tower.example/c',
          method: 'PATCH',
          deviceNpub: 'npub1device',
          allowed: true,
          outcome: 'signed',
        ),
      );

      final audit = await store.listAudit();

      expect(audit, hasLength(2));
      expect(audit.first.method, 'PATCH');
      expect(audit.last.method, 'POST');

      await store.clearAudit();

      expect(await store.listAudit(), isEmpty);
    });
  });
}
