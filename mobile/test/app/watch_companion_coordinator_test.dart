import 'package:buzz/app/watch_companion_coordinator.dart';
import 'package:buzz/features/activity/feed_item.dart';
import 'package:buzz/features/channels/channel.dart';
import 'package:buzz/shared/community/community.dart';
import 'package:buzz/shared/watch/watch_agent_candidates.dart';
import 'package:buzz/shared/watch/watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _requester =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _candidate =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _digest =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

FeedItem _item({
  required String id,
  required int kind,
  required int createdAt,
  required String content,
  required String channelId,
  required List<List<String>> tags,
  String pubkey = _requester,
  String category = 'mention',
}) {
  return FeedItem(
    id: id,
    kind: kind,
    pubkey: pubkey,
    content: content,
    createdAt: createdAt,
    channelId: channelId,
    channelName: '',
    tags: tags,
    category: category,
  );
}

Channel _channel(String id, String name, String type) => Channel(
  id: id,
  name: name,
  channelType: type,
  visibility: 'private',
  description: '',
  createdBy: _me,
  createdAt: DateTime.utc(2026, 7, 26),
  memberCount: 2,
  isMember: true,
);

void main() {
  final now = DateTime.utc(2026, 7, 26, 12);
  final community = Community(
    id: 'zion',
    name: 'Zion',
    relayUrl: 'https://relay.example',
    pubkey: _me,
    addedAt: now,
  );

  test(
    'derives DM, mention, and approval context from app provider values',
    () {
      final coordinator = WatchCompanionCoordinator();
      final approval = _item(
        id: 'approval',
        kind: 46010,
        createdAt: 100,
        content: 'Ship the release?',
        channelId: 'ops',
        category: 'needs_action',
        tags: [
          ['d', _digest],
          ['p', _me],
          ['h', 'ops'],
          ['agent', _requester],
          ['expiration', '${now.millisecondsSinceEpoch ~/ 1000 + 300}'],
        ],
      );
      final dm = _item(
        id: 'dm',
        kind: 9,
        createdAt: 200,
        content: 'Private hello',
        channelId: 'dm-1',
        tags: [
          ['h', 'dm-1'],
          ['p', _me],
        ],
      );
      final mention = _item(
        id: 'mention',
        kind: 40002,
        createdAt: 150,
        content: '@Aiden take a look',
        channelId: 'general',
        tags: [
          ['h', 'general'],
          ['p', _me],
        ],
      );
      final activity = HomeFeedResponse(
        mentions: [dm, mention],
        needsAction: [approval],
        activity: const [],
        agentActivity: const [],
      );

      final snapshot = coordinator.buildSnapshot(
        activeCommunity: community,
        currentPubkey: _me,
        activity: activity,
        channels: [
          _channel('ops', 'Operations', 'stream'),
          _channel('dm-1', 'DM', 'dm'),
          _channel('general', 'General', 'stream'),
        ],
        senderLabels: const {_requester: 'Architect'},
        agents: const [
          WatchAgentDirectoryInput(
            pubkey: _candidate,
            displayName: 'Builder',
            isRegistered: true,
            canInvoke: true,
            channelIds: ['ops'],
          ),
        ],
        presenceByPubkey: {
          _candidate: WatchAgentPresence(
            status: WatchAgentPresenceStatus.online,
            expiresAt: now.add(const Duration(minutes: 2)),
          ),
        },
        now: now,
      );

      expect(snapshot.items.map((item) => item.kind), [
        WatchItemKind.approval,
        WatchItemKind.directMessage,
        WatchItemKind.mention,
      ]);
      expect(snapshot.items.first.senderLabel, 'Architect');
      expect(snapshot.items.first.channelLabel, 'Operations');
      expect(
        snapshot.items.first.allowedActions,
        contains(WatchActionKind.passToAgent),
      );
      expect(snapshot.items.first.eligibleAgents.single.pubkey, _candidate);
    },
  );

  test('locally resolved approvals remain absent on the next snapshot', () {
    final coordinator = WatchCompanionCoordinator();
    final activity = HomeFeedResponse(
      mentions: const [],
      needsAction: [
        _item(
          id: 'approval',
          kind: 46010,
          createdAt: 100,
          content: 'Approve?',
          channelId: 'ops',
          category: 'needs_action',
          tags: [
            ['d', _digest],
            ['p', _me],
            ['h', 'ops'],
            ['expiration', '${now.millisecondsSinceEpoch ~/ 1000 + 300}'],
          ],
        ),
      ],
      activity: const [],
      agentActivity: const [],
    );

    coordinator.markResolved('approval');
    final snapshot = coordinator.buildSnapshot(
      activeCommunity: community,
      currentPubkey: _me,
      activity: activity,
      channels: [_channel('ops', 'Operations', 'stream')],
      now: now,
    );

    expect(snapshot.items, isEmpty);
  });
}
