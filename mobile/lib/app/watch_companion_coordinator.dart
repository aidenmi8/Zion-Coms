import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'push_companion_provider.dart';
import '../features/activity/activity_provider.dart';
import '../features/activity/feed_item.dart';
import '../features/channels/channel.dart';
import '../features/channels/channel_management_provider.dart';
import '../features/channels/channels_provider.dart';
import '../features/channels/mentions/mention_candidates_provider.dart';
import '../features/profile/user_cache_provider.dart';
import '../shared/community/community.dart';
import '../shared/community/community_provider.dart';
import '../shared/apple/apple_companion_channel.dart';
import '../shared/deeplink/pending_deep_link_provider.dart';
import '../shared/relay/nostr_models.dart';
import '../shared/relay/relay_session.dart';
import '../shared/relay/signed_event_relay.dart';
import '../shared/watch/watch_action_ledger.dart';
import '../shared/watch/watch_action_service.dart';
import '../shared/watch/watch_agent_candidates.dart';
import '../shared/watch/watch_inbox_mapper.dart';
import '../shared/watch/watch_models.dart';

typedef WatchActionExecutor =
    Future<WatchActionResult> Function(WatchActionRequest request);

/// Owns the one native action stream and keeps transport concerns separate
/// from the phone-owned relay action service.
class WatchPhoneBridgeCoordinator {
  final AppleWatchBridgeClient _bridge;
  final WatchActionExecutor _execute;
  StreamSubscription<WatchActionRequest>? _actionSubscription;

  WatchPhoneBridgeCoordinator({
    required AppleWatchBridgeClient bridge,
    required WatchActionExecutor execute,
  }) : _bridge = bridge,
       _execute = execute;

  void start() {
    _actionSubscription ??= _bridge.watchActions().listen(
      (request) => unawaited(_handle(request)),
      onError: (_) {},
    );
  }

  Future<void> publish(WatchInboxSnapshot? snapshot) async {
    if (snapshot == null) {
      await _bridge.clearWatchSnapshot();
    } else {
      await _bridge.publishWatchSnapshot(snapshot);
    }
  }

  Future<void> dispose() async {
    await _actionSubscription?.cancel();
    _actionSubscription = null;
  }

  Future<void> _handle(WatchActionRequest request) async {
    final result = await _execute(request);
    await _bridge.completeWatchAction(result);
  }
}

class WatchCompanionCoordinator {
  final WatchInboxMapper _mapper;
  final Set<String> _locallyResolvedItemIds = {};

  WatchCompanionCoordinator({
    WatchInboxMapper mapper = const WatchInboxMapper(),
  }) : _mapper = mapper;

  void markResolved(String itemId) {
    _locallyResolvedItemIds.add(itemId);
  }

  void resetResolvedItems() {
    _locallyResolvedItemIds.clear();
  }

  WatchInboxSnapshot buildSnapshot({
    required Community activeCommunity,
    required String currentPubkey,
    required HomeFeedResponse activity,
    required List<Channel> channels,
    Map<String, String> senderLabels = const {},
    List<WatchAgentDirectoryInput> agents = const [],
    Map<String, WatchAgentPresence> presenceByPubkey = const {},
    DateTime? now,
  }) {
    final generatedAt = (now ?? DateTime.now()).toUtc();
    final channelById = {for (final channel in channels) channel.id: channel};
    final feedById = <String, FeedItem>{};
    for (final item in [...activity.mentions, ...activity.needsAction]) {
      if (_locallyResolvedItemIds.contains(item.id)) continue;
      final existing = feedById[item.id];
      if (existing == null || item.createdAt > existing.createdAt) {
        feedById[item.id] = item;
      }
    }

    final eligibleByDigest = <String, List<WatchAgentSummary>>{};
    for (final item in feedById.values) {
      if (item.kind != EventKind.workflowApprovalRequested) continue;
      final digest = _tagValue(item.tags, 'd');
      final channelId = item.channelId ?? _tagValue(item.tags, 'h');
      if (digest == null || channelId == null) continue;
      eligibleByDigest[digest] = buildWatchAgentCandidates(
        agents: agents,
        presenceByPubkey: presenceByPubkey,
        channelId: channelId,
        actorPubkey: currentPubkey,
        requesterPubkey: _tagValue(item.tags, 'agent'),
        now: generatedAt,
      );
    }

    final sources = <WatchInboxSource>[];
    for (final item in feedById.values) {
      final channel = item.channelId == null
          ? null
          : channelById[item.channelId];
      final senderPubkey = item.kind == EventKind.workflowApprovalRequested
          ? _tagValue(item.tags, 'agent') ?? item.pubkey
          : item.pubkey;
      final senderKey = senderPubkey.toLowerCase();
      sources.add(
        WatchInboxSource(
          communityId: activeCommunity.id,
          event: NostrEvent(
            id: item.id,
            pubkey: item.pubkey,
            createdAt: item.createdAt,
            kind: item.kind,
            tags: item.tags,
            content: item.content,
            sig: '',
          ),
          senderLabel:
              senderLabels[senderKey] ??
              _shortIdentity(senderPubkey, fallback: 'Zion agent'),
          channelLabel: channel?.displayLabel(currentPubkey: currentPubkey),
          isDirectMessage: channel?.isDm ?? false,
        ),
      );
    }

    return _mapper.map(
      communityId: activeCommunity.id,
      communityName: activeCommunity.name,
      currentPubkey: currentPubkey,
      sources: sources,
      eligibleAgentsByApprovalDigest: eligibleByDigest,
      now: generatedAt,
    );
  }
}

String? _tagValue(List<List<String>> tags, String key) {
  for (final tag in tags) {
    if (tag.length >= 2 && tag.first == key) return tag[1];
  }
  return null;
}

String _shortIdentity(String value, {required String fallback}) {
  if (value.isEmpty) return fallback;
  return value.length > 8 ? '${value.substring(0, 8)}…' : value;
}

final watchCompanionCoordinatorProvider = Provider<WatchCompanionCoordinator>((
  ref,
) {
  return WatchCompanionCoordinator();
});

/// Current complete snapshot for the dependent watch companion.
final watchInboxSnapshotProvider = Provider<WatchInboxSnapshot?>((ref) {
  final community = ref.watch(activeCommunityProvider).asData?.value;
  final currentPubkey = ref.watch(currentPubkeyProvider);
  final activity = ref.watch(activityProvider).asData?.value;
  if (community == null || currentPubkey == null || activity == null) {
    return null;
  }
  final channels = ref.watch(watchChannelIndexProvider).values.toList();
  final profiles = ref.watch(userCacheProvider);
  return ref
      .watch(watchCompanionCoordinatorProvider)
      .buildSnapshot(
        activeCommunity: community,
        currentPubkey: currentPubkey,
        activity: activity,
        channels: channels,
        senderLabels: {
          for (final entry in profiles.entries)
            if (entry.value.displayName?.trim().isNotEmpty == true)
              entry.key.toLowerCase(): entry.value.displayName!.trim(),
        },
        agents: ref.watch(watchAgentDirectoryInputsProvider),
        presenceByPubkey: ref.watch(watchAgentPresenceInputsProvider),
      );
});

final watchActionLedgerProvider = FutureProvider<WatchActionLedger>((ref) {
  return createApplicationSupportWatchActionLedger();
});

final watchPhoneBridgeCoordinatorProvider =
    Provider<WatchPhoneBridgeCoordinator?>((ref) {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
      final coordinator = WatchPhoneBridgeCoordinator(
        bridge: ref.watch(appleWatchBridgeClientProvider),
        execute: (request) async {
          final community = await ref.read(activeCommunityProvider.future);
          final snapshot = ref.read(watchInboxSnapshotProvider);
          final ledger = await ref.read(watchActionLedgerProvider.future);
          final service = WatchActionService(
            signedEventRelay: SignedEventRelay(
              session: ref.read(relaySessionProvider.notifier),
              nsec: community?.nsec,
            ),
            ledger: ledger,
            activeCommunityId: () => community?.id,
            findItem: (communityId, itemId) {
              if (snapshot?.communityId != communityId) return null;
              return snapshot?.items
                  .where((item) => item.itemId == itemId)
                  .firstOrNull;
            },
            onResolved: (itemId) {
              ref.read(watchCompanionCoordinatorProvider).markResolved(itemId);
              ref.invalidate(watchInboxSnapshotProvider);
            },
            onOpenOnPhone: (item) async {
              ref
                  .read(pendingDeepLinkProvider.notifier)
                  .handleUri(
                    Uri(
                      scheme: 'buzz',
                      host: 'message',
                      queryParameters: {
                        'channel': item.channelId!,
                        'id': item.sourceEventId,
                      },
                    ),
                  );
            },
          );
          return service.execute(request);
        },
      );
      coordinator.start();
      ref.onDispose(() {
        unawaited(coordinator.dispose());
      });
      return coordinator;
    });

/// Publishes only the active community snapshot, and clears the watch cache on
/// sign-out or while the active community is unavailable.
final watchPhoneBridgeBindingProvider = Provider<void>((ref) {
  final coordinator = ref.watch(watchPhoneBridgeCoordinatorProvider);
  final snapshot = ref.watch(watchInboxSnapshotProvider);
  if (coordinator == null) return;
  Future.microtask(() async {
    try {
      await coordinator.publish(snapshot);
    } on AppleCompanionException {
      // The app remains fully usable when WatchConnectivity is unavailable.
    }
  });
});
