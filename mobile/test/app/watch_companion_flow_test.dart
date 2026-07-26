import 'dart:async';

import 'package:buzz/app/watch_companion_coordinator.dart';
import 'package:buzz/features/activity/feed_item.dart';
import 'package:buzz/features/channels/channel.dart';
import 'package:buzz/shared/apple/apple_companion_channel.dart';
import 'package:buzz/shared/community/community.dart';
import 'package:buzz/shared/relay/nostr_models.dart';
import 'package:buzz/shared/relay/signed_event_relay.dart';
import 'package:buzz/shared/watch/watch_action_ledger.dart';
import 'package:buzz/shared/watch/watch_action_service.dart';
import 'package:buzz/shared/watch/watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _agent =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _digest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _requestId =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _mentionId =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

class _MemoryLedgerStorage implements WatchActionLedgerStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String contents) async => value = contents;
}

class _Submission {
  const _Submission({
    required this.kind,
    required this.content,
    required this.tags,
  });

  final int kind;
  final String content;
  final List<List<String>> tags;
}

class _FakeRelay implements SignedEventRelay {
  final submissions = <_Submission>[];

  @override
  String? get pubkey => _me;

  @override
  Future<NostrEvent> submit({
    required int kind,
    required String content,
    required List<List<String>> tags,
    int? createdAt,
  }) async {
    submissions.add(_Submission(kind: kind, content: content, tags: tags));
    return const NostrEvent(
      id: 'accepted',
      pubkey: _me,
      createdAt: 0,
      kind: 0,
      tags: [],
      content: 'response:{"status":"accepted"}',
      sig: '',
    );
  }
}

class _FakeWatchBridge implements AppleWatchBridgeClient {
  final actions = StreamController<WatchActionRequest>.broadcast();
  final snapshots = <WatchInboxSnapshot>[];
  final results = <WatchActionResult>[];

  @override
  Future<void> clearWatchSnapshot() async {}

  @override
  Future<void> completeWatchAction(WatchActionResult result) async {
    results.add(result);
  }

  @override
  Future<void> publishWatchSnapshot(WatchInboxSnapshot snapshot) async {
    snapshots.add(snapshot);
  }

  @override
  Stream<WatchActionRequest> watchActions() => actions.stream;

  Future<void> dispose() => actions.close();
}

void main() {
  final now = DateTime.utc(2026, 7, 26, 12);
  final community = Community(
    id: 'zion',
    name: 'Zion',
    relayUrl: 'https://relay.example',
    pubkey: _me,
    addedAt: now,
  );
  final channels = [
    Channel(
      id: 'ops',
      name: 'Operations',
      channelType: 'stream',
      visibility: 'private',
      description: '',
      createdBy: _me,
      createdAt: now,
      memberCount: 2,
      isMember: true,
    ),
    Channel(
      id: 'general',
      name: 'General',
      channelType: 'stream',
      visibility: 'open',
      description: '',
      createdBy: _me,
      createdAt: now,
      memberCount: 4,
      isMember: true,
    ),
  ];
  final activity = HomeFeedResponse(
    mentions: [
      FeedItem(
        id: _mentionId,
        kind: EventKind.streamMessageV2,
        pubkey: _agent,
        content: '@Aiden review the launch note',
        createdAt: now.millisecondsSinceEpoch ~/ 1000 + 20,
        channelId: 'general',
        channelName: 'General',
        tags: const [
          ['h', 'general'],
          ['p', _me],
        ],
        category: 'mention',
      ),
    ],
    needsAction: [
      FeedItem(
        id: _requestId,
        kind: EventKind.workflowApprovalRequested,
        pubkey: _agent,
        content: 'Ship the Zion Watch build?',
        createdAt: now.millisecondsSinceEpoch ~/ 1000,
        channelId: 'ops',
        channelName: 'Operations',
        tags: [
          ['d', _digest],
          ['p', _me],
          ['h', 'ops'],
          ['agent', _agent],
          ['expiration', '${now.millisecondsSinceEpoch ~/ 1000 + 300}'],
        ],
        category: 'needs_action',
      ),
    ],
    activity: const [],
    agentActivity: const [],
  );

  test(
    'arrival through duplicate action publishes one signed command and a fresh queue',
    () async {
      final domain = WatchCompanionCoordinator();
      final bridge = _FakeWatchBridge();
      final relay = _FakeRelay();
      var snapshot = domain.buildSnapshot(
        activeCommunity: community,
        currentPubkey: _me,
        activity: activity,
        channels: channels,
        senderLabels: const {_agent: 'Release agent'},
        now: now,
      );
      var snapshotChanged = false;
      final service = WatchActionService(
        signedEventRelay: relay,
        ledger: WatchActionLedger(storage: _MemoryLedgerStorage()),
        activeCommunityId: () => community.id,
        findItem: (communityId, itemId) => snapshot.items
            .where(
              (item) =>
                  item.communityId == communityId && item.itemId == itemId,
            )
            .firstOrNull,
        now: () => now,
        onResolved: (itemId) {
          domain.markResolved(itemId);
          snapshotChanged = true;
        },
      );
      final phone = WatchPhoneBridgeCoordinator(
        bridge: bridge,
        execute: (request) async {
          final result = await service.execute(request);
          if (snapshotChanged) {
            snapshot = domain.buildSnapshot(
              activeCommunity: community,
              currentPubkey: _me,
              activity: activity,
              channels: channels,
              senderLabels: const {_agent: 'Release agent'},
              now: now,
            );
            await bridge.publishWatchSnapshot(snapshot);
            snapshotChanged = false;
          }
          return result;
        },
      );
      phone.start();
      await phone.publish(snapshot);

      expect(snapshot.items.map((item) => item.kind), [
        WatchItemKind.approval,
        WatchItemKind.mention,
      ]);

      const request = WatchActionRequest(
        actionId: '10000000-0000-4000-8000-000000000001',
        communityId: 'zion',
        itemId: _requestId,
        action: WatchActionKind.approve,
      );
      bridge.actions.add(request);
      await pumpEventQueue(times: 20);

      expect(relay.submissions, hasLength(1));
      expect(
        relay.submissions.single.kind,
        EventKind.workflowApprovalGrantCommand,
      );
      expect(relay.submissions.single.tags, [
        ['d', _digest],
      ]);
      expect(bridge.results.single.outcome, WatchActionOutcome.accepted);
      expect(bridge.snapshots, hasLength(2));
      expect(bridge.snapshots.last.items.map((item) => item.itemId), [
        _mentionId,
      ]);

      bridge.actions.add(request);
      await pumpEventQueue(times: 20);

      expect(relay.submissions, hasLength(1));
      expect(bridge.results, hasLength(2));
      expect(
        bridge.results.map((result) => result.outcome),
        everyElement(WatchActionOutcome.accepted),
      );
      expect(
        bridge.snapshots,
        hasLength(2),
        reason: 'the duplicate result must not republish an unchanged snapshot',
      );

      await phone.dispose();
      await bridge.dispose();
    },
  );
}
