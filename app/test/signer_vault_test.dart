import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_app/src/core/nostr_crypto.dart';
import 'package:wingman_app/src/core/signer_vault.dart';

void main() {
  const secretHex =
      '0000000000000000000000000000000000000000000000000000000000000001';

  test('encrypts nsec locally and unlocks with PIN', () async {
    final nsec = NostrCrypto.importIdentity(secretHex).nsec;
    final localStore = MemorySignerVaultLocalStore();
    final secretStore = MemorySignerVaultSecretStore();
    final vault = SignerVault(
      localStore: localStore,
      secretStore: secretStore,
    );

    final created = await vault.create(nsec: nsec, pin: '123456');
    expect(created.nsec, nsec);

    final record = await vault.loadRecord();
    expect(record, isNotNull);
    expect(record!.npub, created.npub);
    expect(record.ciphertext, isNot(contains('nsec')));

    final unlocked = await vault.unlock(pin: '123456');
    expect(unlocked.nsec, nsec);
    expect(unlocked.npub, created.npub);
  });

  test('rejects wrong PIN', () async {
    final nsec = NostrCrypto.importIdentity(secretHex).nsec;
    final vault = SignerVault(
      localStore: MemorySignerVaultLocalStore(),
      secretStore: MemorySignerVaultSecretStore(),
    );
    await vault.create(nsec: nsec, pin: '123456');

    expect(
      () => vault.unlock(pin: '654321'),
      throwsA(isA<SignerVaultException>()),
    );
  });
}
