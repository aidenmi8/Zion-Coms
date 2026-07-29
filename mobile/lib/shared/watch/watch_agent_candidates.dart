import 'watch_models.dart';

enum WatchAgentPresenceStatus { online, away, offline }

class WatchAgentPresence {
  final WatchAgentPresenceStatus status;
  final DateTime expiresAt;

  const WatchAgentPresence({required this.status, required this.expiresAt});
}

class WatchAgentDirectoryInput {
  final String pubkey;
  final String displayName;
  final bool isRegistered;
  final bool canInvoke;
  final List<String> channelIds;
  final DateTime? recentUseAt;

  const WatchAgentDirectoryInput({
    required this.pubkey,
    required this.displayName,
    required this.isRegistered,
    required this.canInvoke,
    required this.channelIds,
    this.recentUseAt,
  });
}

List<WatchAgentSummary> buildWatchAgentCandidates({
  required Iterable<WatchAgentDirectoryInput> agents,
  required Map<String, WatchAgentPresence> presenceByPubkey,
  required String channelId,
  required String actorPubkey,
  required String? requesterPubkey,
  required DateTime now,
  int maxCandidates = 8,
}) {
  final actor = actorPubkey.toLowerCase();
  final requester = requesterPubkey?.toLowerCase();
  final eligible =
      <({WatchAgentDirectoryInput agent, WatchAgentPresence presence})>[];

  for (final agent in agents) {
    final pubkey = agent.pubkey.toLowerCase();
    final presence = presenceByPubkey[pubkey];
    if (!agent.isRegistered ||
        !agent.canInvoke ||
        pubkey == actor ||
        pubkey == requester ||
        !agent.channelIds.contains(channelId) ||
        presence == null ||
        !presence.expiresAt.toUtc().isAfter(now.toUtc()) ||
        presence.status == WatchAgentPresenceStatus.offline) {
      continue;
    }
    eligible.add((agent: agent, presence: presence));
  }

  eligible.sort((left, right) {
    final availabilityOrder = _presenceRank(
      left.presence.status,
    ).compareTo(_presenceRank(right.presence.status));
    if (availabilityOrder != 0) return availabilityOrder;

    final leftUse = left.agent.recentUseAt;
    final rightUse = right.agent.recentUseAt;
    if (leftUse != null && rightUse != null) {
      final useOrder = rightUse.compareTo(leftUse);
      if (useOrder != 0) return useOrder;
    } else if (leftUse != null) {
      return -1;
    } else if (rightUse != null) {
      return 1;
    }

    final nameOrder = left.agent.displayName.toLowerCase().compareTo(
      right.agent.displayName.toLowerCase(),
    );
    return nameOrder != 0
        ? nameOrder
        : left.agent.pubkey.compareTo(right.agent.pubkey);
  });

  final selected = eligible.take(maxCandidates).toList(growable: false);
  return [
    for (var index = 0; index < selected.length; index++)
      WatchAgentSummary(
        pubkey: selected[index].agent.pubkey.toLowerCase(),
        displayName: selected[index].agent.displayName,
        availability:
            selected[index].presence.status == WatchAgentPresenceStatus.online
            ? WatchAgentAvailability.online
            : WatchAgentAvailability.away,
        sortRank: index,
      ),
  ];
}

int _presenceRank(WatchAgentPresenceStatus status) => switch (status) {
  WatchAgentPresenceStatus.online => 0,
  WatchAgentPresenceStatus.away => 1,
  WatchAgentPresenceStatus.offline => 2,
};
