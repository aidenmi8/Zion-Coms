import 'package:buzz/shared/watch/watch_agent_candidates.dart';
import 'package:buzz/shared/watch/watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _actor =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _requester =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _pk(String character) => List.filled(64, character).join();

WatchAgentDirectoryInput _agent(
  String key,
  String name, {
  bool registered = true,
  bool canInvoke = true,
  List<String> channelIds = const ['channel-1'],
  DateTime? recentUseAt,
}) {
  return WatchAgentDirectoryInput(
    pubkey: _pk(key),
    displayName: name,
    isRegistered: registered,
    canInvoke: canInvoke,
    channelIds: channelIds,
    recentUseAt: recentUseAt,
  );
}

void main() {
  final now = DateTime.utc(2026, 7, 26, 12);

  test('keeps only invocable current-channel agents with live presence', () {
    final agents = [
      _agent('c', 'Online recent', recentUseAt: now),
      _agent('d', 'Away agent'),
      _agent('e', 'Offline'),
      _agent('f', 'Expired'),
      _agent('1', 'Unregistered', registered: false),
      _agent('2', 'Forbidden', canInvoke: false),
      _agent('3', 'Wrong channel', channelIds: const ['channel-2']),
      _agent('a', 'Actor'),
      _agent('b', 'Requester'),
    ];
    final presence = {
      _pk('c'): WatchAgentPresence(
        status: WatchAgentPresenceStatus.online,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
      _pk('d'): WatchAgentPresence(
        status: WatchAgentPresenceStatus.away,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
      _pk('e'): WatchAgentPresence(
        status: WatchAgentPresenceStatus.offline,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
      _pk('f'): WatchAgentPresence(
        status: WatchAgentPresenceStatus.online,
        expiresAt: now.subtract(const Duration(seconds: 1)),
      ),
      for (final key in ['1', '2', '3', 'a', 'b'])
        _pk(key): WatchAgentPresence(
          status: WatchAgentPresenceStatus.online,
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
    };

    final result = buildWatchAgentCandidates(
      agents: agents,
      presenceByPubkey: presence,
      channelId: 'channel-1',
      actorPubkey: _actor,
      requesterPubkey: _requester,
      now: now,
    );

    expect(result.map((candidate) => candidate.displayName), [
      'Online recent',
      'Away agent',
    ]);
    expect(result.first.availability, WatchAgentAvailability.online);
    expect(result.last.availability, WatchAgentAvailability.away);
  });

  test('sorts by online, recent use, then display name', () {
    final agents = [
      _agent('c', 'Zulu', recentUseAt: now.subtract(const Duration(hours: 2))),
      _agent('d', 'Beta', recentUseAt: now.subtract(const Duration(hours: 1))),
      _agent('e', 'Alpha', recentUseAt: now.subtract(const Duration(hours: 1))),
      _agent('f', 'Away recent', recentUseAt: now),
    ];
    final presence = {
      for (final agent in agents)
        agent.pubkey: WatchAgentPresence(
          status: agent.displayName.startsWith('Away')
              ? WatchAgentPresenceStatus.away
              : WatchAgentPresenceStatus.online,
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
    };

    final result = buildWatchAgentCandidates(
      agents: agents,
      presenceByPubkey: presence,
      channelId: 'channel-1',
      actorPubkey: _actor,
      requesterPubkey: _requester,
      now: now,
    );

    expect(result.map((candidate) => candidate.displayName), [
      'Alpha',
      'Beta',
      'Zulu',
      'Away recent',
    ]);
    expect(result.map((candidate) => candidate.sortRank), [0, 1, 2, 3]);
  });
}
