import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../shared/apple/apple_companion_channel.dart';
import '../shared/auth/auth.dart';
import '../shared/crypto/nip44.dart';
import '../shared/watch/push_descriptor.dart';
import '../shared/watch/push_lease_coordinator.dart';

final appleCompanionChannelProvider = Provider<AppleCompanionChannel>((ref) {
  return AppleCompanionChannel();
});

final appleCompanionClientProvider = Provider<AppleCompanionClient>((ref) {
  return ref.watch(appleCompanionChannelProvider);
});

final appleWatchBridgeClientProvider = Provider<AppleWatchBridgeClient>((ref) {
  return ref.watch(appleCompanionChannelProvider);
});

final pushLeaseCoordinatorProvider = Provider<PushLeaseCoordinator>((ref) {
  return PushLeaseCoordinator(
    descriptorSource: HttpPushDescriptorSource(),
    appleClient: ref.watch(appleCompanionClientProvider),
    publisher: HttpPushLeasePublisher(),
    store: SecurePushLeaseStore(),
    encrypt: (plaintext, privateKeyHex, recipientPubkey) {
      final conversationKey = getConversationKey(
        privateKeyHex,
        recipientPubkey,
      );
      return nip44Encrypt(conversationKey, plaintext);
    },
  );
});

class PushCompanionController extends Notifier<PushCompanionState> {
  PushLeaseContext? _context;
  StreamSubscription<int>? _endpointEpochSubscription;
  int _reconcileGeneration = 0;

  @override
  PushCompanionState build() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _endpointEpochSubscription ??= ref
          .read(appleCompanionClientProvider)
          .endpointEpochChanges
          .listen(
            (_) => unawaited(_renewAfterEndpointChange()),
            onError: (_) {},
          );
    }
    ref.onDispose(() {
      _endpointEpochSubscription?.cancel();
      _endpointEpochSubscription = null;
    });
    return const PushCompanionState(PushCompanionStatus.off);
  }

  Future<void> reconcileContext(PushLeaseContext? context) async {
    _context = context;
    final generation = ++_reconcileGeneration;
    final coordinator = ref.read(pushLeaseCoordinatorProvider);
    await coordinator.reconcile(context);
    if (generation == _reconcileGeneration && _context == context) {
      state = coordinator.state;
    }
  }

  Future<void> enable() async {
    final context = _context;
    if (context == null) return;
    state = const PushCompanionState(PushCompanionStatus.enabling);
    final coordinator = ref.read(pushLeaseCoordinatorProvider);
    await coordinator.enable(context);
    if (_context == context) state = coordinator.state;
  }

  Future<void> disableForSignOut() async {
    _context = null;
    ++_reconcileGeneration;
    final coordinator = ref.read(pushLeaseCoordinatorProvider);
    await coordinator.reconcile(null);
    state = coordinator.state;
  }

  Future<void> _renewAfterEndpointChange() async {
    final context = _context;
    if (context == null) return;
    final coordinator = ref.read(pushLeaseCoordinatorProvider);
    await coordinator.renewAfterEndpointChange(context);
    if (_context == context) state = coordinator.state;
  }
}

final pushCompanionControllerProvider =
    NotifierProvider<PushCompanionController, PushCompanionState>(
      PushCompanionController.new,
    );

/// Binds the passive push lifecycle to auth/community changes. Merely reading
/// this provider can restore an existing lease, but never requests permission.
final pushCompanionBindingProvider = Provider<void>((ref) {
  final auth = ref.watch(authProvider).value;
  final context = _pushContext(auth?.community);
  Future.microtask(() {
    ref
        .read(pushCompanionControllerProvider.notifier)
        .reconcileContext(context);
  });
});

PushLeaseContext? _pushContext(Community? community) {
  final nsec = community?.nsec;
  if (community == null || nsec == null || nsec.isEmpty) return null;
  try {
    final decoded = nostr.Nip19.decode(payload: nsec);
    if (decoded.data.length != 64) return null;
    final pubkey = community.pubkey ?? nostr.Keys(decoded.data).public;
    return PushLeaseContext(
      communityId: community.id,
      relayBaseUrl: community.relayUrl,
      pubkey: pubkey.toLowerCase(),
      privateKeyHex: decoded.data,
      appProfileId: applePushAppProfileId,
    );
  } on Object {
    return null;
  }
}
