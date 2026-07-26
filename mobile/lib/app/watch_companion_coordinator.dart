import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/activity/activity_provider.dart';
import '../features/activity/feed_item.dart';
import '../features/channels/channel.dart';
import '../features/channels/channel_management_provider.dart';
import '../features/channels/channels_provider.dart';
import '../features/channels/mentions/mention_candidates_provider.dart';
import '../features/profile/user_cache_provider.dart';
import '../shared/community/community.dart';
import '../shared/community/community_provider.dart';
import '../shared/relay/nostr_models.dart';
import '../shared/watch/watch_agent_candidates.dart';
import '../shared/watch/watch_inbox_mapper.dart';
import '../shared/watch/watch_models.dart';

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
