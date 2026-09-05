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
  test('creation cannot overwrite an existing or unreadable vault', () async {
    final local = MemorySignerVaultLocalStore();
    final secrets = MemorySignerVaultSecretStore();
    final vault = SignerVault(localStore: local, secretStore: secrets);
    final first = await vault.create(nsec: secretHex, pin: '1234');
    final before = await local.getString('wingman.signer.vault.v1');
    await expectLater(vault.create(nsec: '2'.padLeft(64, '0'), pin: '5678'),
        throwsA(isA<SignerVaultException>()));
    expect(await local.getString('wingman.signer.vault.v1'), before);
    expect((await vault.unlock(pin: '1234')).npub, first.npub);
    expect(before, isNot(contains(first.nsec)));
    expect(before, isNot(contains(secretHex)));
    await local.setString('wingman.signer.vault.v1', 'unreadable');
    await expectLater(vault.create(nsec: secretHex, pin: '1234'),
        throwsA(isA<SignerVaultException>()));
    expect(await local.getString('wingman.signer.vault.v1'), 'unreadable');
  });

  test('simultaneous creation cannot replace the first identity', () async {
    final local = MemorySignerVaultLocalStore();
    final secrets = MemorySignerVaultSecretStore();
    final vault = SignerVault(localStore: local, secretStore: secrets);
    final other = SignerVault(localStore: local, secretStore: secrets);
    final first = vault.create(nsec: secretHex, pin: '1234');
    await expectLater(other.create(nsec: '2'.padLeft(64, '0'), pin: '5678'),
        throwsA(isA<SignerVaultException>()));
    final created = await first;
    expect((await vault.unlock(pin: '1234')).npub, created.npub);
  });
}
