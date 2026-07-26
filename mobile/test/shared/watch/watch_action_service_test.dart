import 'dart:async';

import 'package:buzz/shared/relay/nostr_models.dart';
import 'package:buzz/shared/relay/signed_event_relay.dart';
import 'package:buzz/shared/watch/watch_action_ledger.dart';
import 'package:buzz/shared/watch/watch_action_service.dart';
import 'package:buzz/shared/watch/watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _target =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _repeat(String character) => List.filled(64, character).join();

class _MemoryLedgerStorage implements WatchActionLedgerStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String contents) async => value = contents;
}

class _Submission {
  final int kind;
  final String content;
  final List<List<String>> tags;

  const _Submission({
    required this.kind,
    required this.content,
    required this.tags,
  });
}

class _FakeRelay implements SignedEventRelay {
  final List<_Submission> submissions = [];
  Object? error;

  @override
  String? get pubkey => _repeat('c');

  @override
  Future<NostrEvent> submit({
    required int kind,
    required String content,
    required List<List<String>> tags,
    int? createdAt,
  }) async {
    submissions.add(_Submission(kind: kind, content: content, tags: tags));
    if (error case final failure?) throw failure;
    return const NostrEvent(
      id: 'accepted',
      pubkey: '',
      createdAt: 0,
      kind: 0,
      tags: [],
      content: 'response:{"status":"accepted"}',
      sig: '',
    );
  }
}

WatchInboxItem _approval({String communityId = 'zion', DateTime? expiresAt}) {
  return WatchInboxItem(
    itemId: 'approval-event',
    kind: WatchItemKind.approval,
    communityId: communityId,
    channelId: 'channel-1',
    title: 'Approval requested',
    senderLabel: 'Agent',
    channelLabel: 'Operations',
    body: 'Ship the build?',
    createdAt: DateTime.utc(2026, 7, 26, 11),
    expiresAt: expiresAt ?? DateTime.utc(2026, 7, 26, 13),
    sourceEventId: _repeat('d'),
    isTruncated: false,
    allowedActions: const {
      WatchActionKind.approve,
      WatchActionKind.deny,
      WatchActionKind.passToAgent,
      WatchActionKind.openOnPhone,
    },
    eligibleAgents: const [
      WatchAgentSummary(
        pubkey: _target,
        displayName: 'Builder',
        availability: WatchAgentAvailability.online,
        sortRank: 0,
      ),
    ],
    approvalDigest: _digest,
    requestingAgentPubkey: _repeat('e'),
  );
}

WatchActionRequest _request(
  String actionId,
  WatchActionKind action, {
  String communityId = 'zion',
  String itemId = 'approval-event',
  String? target,
}) {
  return WatchActionRequest(
    actionId: actionId,
    communityId: communityId,
    itemId: itemId,
    action: action,
    targetAgentPubkey: target,
  );
}

WatchActionService _service({
  required _FakeRelay relay,
  required WatchActionLedger ledger,
  WatchInboxItem? item,
  void Function(String itemId)? onResolved,
  Future<void> Function(WatchInboxItem item)? onOpenOnPhone,
}) {
  final approval = item ?? _approval();
  return WatchActionService(
    signedEventRelay: relay,
    ledger: ledger,
    activeCommunityId: () => 'zion',
    findItem: (communityId, itemId) =>
        communityId == approval.communityId && itemId == approval.itemId
        ? approval
        : null,
    now: () => DateTime.utc(2026, 7, 26, 12),
    onResolved: onResolved,
    onOpenOnPhone: onOpenOnPhone,
  );
}

void main() {
  test('builds approve, deny, and Pass commands with bounded tags', () async {
    final relay = _FakeRelay();
    final service = _service(
      relay: relay,
      ledger: WatchActionLedger(storage: _MemoryLedgerStorage()),
    );

    await service.execute(_request('approve-1', WatchActionKind.approve));
    await service.execute(_request('deny-1', WatchActionKind.deny));
    await service.execute(
      _request('pass-1', WatchActionKind.passToAgent, target: _target),
    );

    expect(relay.submissions.map((submission) => submission.kind), [
      EventKind.workflowApprovalGrantCommand,
      EventKind.workflowApprovalDenyCommand,
      EventKind.workflowApprovalPassCommand,
    ]);
    for (final submission in relay.submissions) {
      expect(submission.tags.where((tag) => tag.first == 'd').toList(), [
        ['d', _digest],
      ]);
    }
    final pass = relay.submissions.last;
    expect(pass.tags.where((tag) => tag.first == 'p').toList(), [
      ['p', _target],
    ]);
    expect(pass.tags, anyElement(equals(['e', _repeat('d')])));
    expect(pass.tags, anyElement(equals(['h', 'channel-1'])));
  });

  test(
    'duplicate action IDs replay the original result and publish once',
    () async {
      final relay = _FakeRelay();
      final service = _service(
        relay: relay,
        ledger: WatchActionLedger(storage: _MemoryLedgerStorage()),
      );
      final request = _request('approve-1', WatchActionKind.approve);

      final first = await service.execute(request);
      final replay = await service.execute(request);

      expect(first.outcome, WatchActionOutcome.accepted);
      expect(replay.outcome, WatchActionOutcome.accepted);
      expect(relay.submissions, hasLength(1));
    },
  );

  test(
    'stale community, missing item, and expired request fail unsigned',
    () async {
      for (final request in [
        _request(
          'wrong-community',
          WatchActionKind.approve,
          communityId: 'other',
        ),
        _request('missing-item', WatchActionKind.approve, itemId: 'missing'),
      ]) {
        final relay = _FakeRelay();
        final result = await _service(
          relay: relay,
          ledger: WatchActionLedger(storage: _MemoryLedgerStorage()),
        ).execute(request);
        expect(result.outcome, isNot(WatchActionOutcome.accepted));
        expect(relay.submissions, isEmpty);
      }

      final relay = _FakeRelay();
      final result = await _service(
        relay: relay,
        ledger: WatchActionLedger(storage: _MemoryLedgerStorage()),
        item: _approval(expiresAt: DateTime.utc(2026, 7, 26, 11, 59)),
      ).execute(_request('expired', WatchActionKind.approve));
      expect(result.outcome, WatchActionOutcome.alreadyResolved);
      expect(relay.submissions, isEmpty);
    },
  );

  test(
    'accepted terminal action removes the local item after relay acceptance',
    () async {
      final removed = Completer<String>();
      final result = await _service(
        relay: _FakeRelay(),
        ledger: WatchActionLedger(storage: _MemoryLedgerStorage()),
        onResolved: removed.complete,
      ).execute(_request('approve-1', WatchActionKind.approve));

      expect(result.outcome, WatchActionOutcome.accepted);
      expect(await removed.future, 'approval-event');
    },
  );

  test('Open on iPhone routes locally without signing or resolving', () async {
    final relay = _FakeRelay();
    final opened = <WatchInboxItem>[];
    final resolved = <String>[];
    final service = _service(
      relay: relay,
      ledger: WatchActionLedger(storage: _MemoryLedgerStorage()),
      onOpenOnPhone: (item) async => opened.add(item),
      onResolved: resolved.add,
    );

    final result = await service.execute(
      _request('open-1', WatchActionKind.openOnPhone),
    );

    expect(result.outcome, WatchActionOutcome.accepted);
    expect(opened.single.itemId, 'approval-event');
    expect(relay.submissions, isEmpty);
    expect(resolved, isEmpty);
  });
}
