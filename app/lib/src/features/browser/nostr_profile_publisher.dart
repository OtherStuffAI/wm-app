import 'dart:convert';

import '../../core/nostr_crypto.dart';
import 'nostr_profile_relay_client.dart';
import 'nostr_profile_store.dart';

class NostrProfilePublisher {
  NostrProfilePublisher({required this.store, required this.relays});
  final NostrProfileStore store;
  final NostrProfileRelayClient relays;

  Future<ProfilePublishResult> publish({
    required String npub,
    required String secret,
    required NostrProfile profile,
  }) async {
    await store.save(npub, profile);
    final identity = NostrCrypto.importIdentity(secret);
    if (identity.npub != npub) {
      throw StateError('Unlock the matching identity before publishing.');
    }
    final event = NostrCrypto.signEvent(secret: secret, event: {
      'kind': 0,
      'tags': <List<String>>[],
      'content': jsonEncode(profile.toKind0Json()),
    });
    return relays.publish(event);
  }
}
