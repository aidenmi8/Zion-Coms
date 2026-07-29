import 'package:buzz/shared/relay/nostr_models.dart';
import 'package:buzz/shared/watch/watch_inbox_mapper.dart';
import 'package:buzz/shared/watch/watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _agent =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _hex(String character) => List.filled(64, character).join();

NostrEvent _event({
  required String id,
  required int kind,
  required int createdAt,
  required String content,
  String pubkey = _agent,
  List<List<String>> tags = const [],
}) {
  return NostrEvent(
    id: id,
    pubkey: pubkey,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
    sig: 'sig',
  );
}

WatchInboxSource _source({
  required String communityId,
  required NostrEvent event,
  bool isDirectMessage = false,
}) {
  return WatchInboxSource(
    communityId: communityId,
    event: event,
    senderLabel: 'Agent',
    channelLabel: 'Operations',
    isDirectMessage: isDirectMessage,
  );
}

void main() {
  const mapper = WatchInboxMapper();
  final now = DateTime.fromMillisecondsSinceEpoch(10_000 * 1000, isUtc: true);

  test(
    'keeps active pending approvals first and orders each kind newest first',
    () {
      final sources = [
        _source(
          communityId: 'other',
          event: _event(
            id: 'other-approval',
            kind: EventKind.workflowApprovalRequested,
            createdAt: 9999,
            content: 'Wrong community',
            tags: [
              ['d', _hex('9')],
              ['p', _me],
              ['expiration', '11000'],
            ],
          ),
        ),
        _source(
          communityId: 'zion',
          event: _event(
            id: 'resolved-request',
            kind: EventKind.workflowApprovalRequested,
            createdAt: 9900,
            content: 'Already done',
            tags: [
              ['d', _hex('1')],
              ['p', _me],
              ['expiration', '11000'],
            ],
          ),
        ),
        _source(
          communityId: 'zion',
          event: _event(
            id: 'resolved-lifecycle',
            kind: EventKind.workflowApprovalGranted,
            createdAt: 9950,
            content: '',
            tags: [
              ['d', _hex('1')],
              ['p', _me],
            ],
          ),
        ),
        _source(
          communityId: 'zion',
          event: _event(
            id: 'approval-old',
            kind: EventKind.workflowApprovalRequested,
            createdAt: 9700,
            content: 'Deploy the relay?',
            tags: [
              ['d', _hex('2')],
              ['p', _me],
              ['h', 'channel-1'],
              ['expiration', '11000'],
              ['agent', _agent],
            ],
          ),
        ),
        _source(
          communityId: 'zion',
          event: _event(
            id: 'approval-new',
            kind: EventKind.workflowApprovalRequested,
            createdAt: 9800,
            content: 'Publish the build?',
            tags: [
              ['d', _hex('3')],
              ['p', _me],
              ['h', 'channel-1'],
              ['expiration', '11000'],
              ['agent', _agent],
            ],
          ),
        ),
        _source(
          communityId: 'zion',
          isDirectMessage: true,
          event: _event(
            id: 'dm-new',
            kind: EventKind.streamMessage,
            createdAt: 9990,
            content: 'Can you review this?',
            tags: [
              ['h', 'dm-1'],
              ['p', _me],
            ],
          ),
        ),
        _source(
          communityId: 'zion',
          event: _event(
            id: 'mention-old',
            kind: EventKind.streamMessageV2,
            createdAt: 9600,
            content: '@Aiden status update',
            tags: [
              ['h', 'channel-1'],
              ['p', _me],
            ],
          ),
        ),
      ];

      final snapshot = mapper.map(
        communityId: 'zion',
        communityName: 'Zion',
        currentPubkey: _me,
        sources: sources,
        now: now,
      );

      expect(snapshot.items.map((item) => item.itemId), [
        'approval-new',
        'approval-old',
        'dm-new',
        'mention-old',
      ]);
      expect(snapshot.items.first.kind, WatchItemKind.approval);
      expect(snapshot.items.first.sourceEventId, 'approval-new');
      expect(snapshot.items.first.approvalDigest, _hex('3'));
      expect(snapshot.items.first.allowedActions, {
        WatchActionKind.approve,
        WatchActionKind.deny,
        WatchActionKind.openOnPhone,
      });
    },
  );

  test('caps the queue at 20 and bodies at 2000 Unicode scalars', () {
    final longBody = List.filled(2005, '🟣').join();
    final sources = [
      for (var index = 0; index < 25; index++)
        _source(
          communityId: 'zion',
          event: _event(
            id: 'mention-$index',
            kind: EventKind.streamMessage,
            createdAt: 9000 + index,
            content: index == 24 ? longBody : 'Message $index',
            tags: [
              ['h', 'channel-1'],
              ['p', _me],
            ],
          ),
        ),
    ];

    final snapshot = mapper.map(
      communityId: 'zion',
      communityName: 'Zion',
      currentPubkey: _me,
      sources: sources,
      now: now,
    );

    expect(snapshot.items, hasLength(20));
    expect(snapshot.items.first.itemId, 'mention-24');
    expect(snapshot.items.first.body.runes, hasLength(2000));
    expect(snapshot.items.first.isTruncated, isTrue);
  });

  test('wire serialization omits the phone-only approval digest', () {
    final snapshot = mapper.map(
      communityId: 'zion',
      communityName: 'Zion',
      currentPubkey: _me,
      sources: [
        _source(
          communityId: 'zion',
          event: _event(
            id: 'approval',
            kind: EventKind.workflowApprovalRequested,
            createdAt: 9800,
            content: 'Approve?',
            tags: [
              ['d', _hex('4')],
              ['p', _me],
              ['expiration', '11000'],
            ],
          ),
        ),
      ],
      now: now,
    );

    final wireItem =
        (snapshot.toWireJson()['items'] as List).single as Map<String, dynamic>;
    expect(wireItem, isNot(contains('approvalDigest')));
    expect(snapshot.schemaVersion, 1);
  });

  test('converts simple Markdown links and emphasis to plain text', () {
    final snapshot = mapper.map(
      communityId: 'zion',
      communityName: 'Zion',
      currentPubkey: _me,
      sources: [
        _source(
          communityId: 'zion',
          event: _event(
            id: 'mention',
            kind: EventKind.streamMessage,
            createdAt: 9800,
            content: '[Review](https://example.com) **now**',
            tags: [
              ['p', _me],
            ],
          ),
        ),
      ],
      now: now,
    );

    expect(snapshot.items.single.body, 'Review now');
  });
}
