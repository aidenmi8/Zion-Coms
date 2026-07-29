import 'dart:async';

import 'package:buzz/features/channels/channel_management_provider.dart';
import 'package:buzz/features/channels/send_message_provider.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;

const _me = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _recipient =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _mentioned =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _channelId = '11111111-1111-4111-8111-111111111111';

class _FakeRelay implements SignedEventRelay {
  List<List<String>>? tags;

  @override
  String? get pubkey => _me;

  @override
  Future<NostrEvent> submit({
    required int kind,
    required String content,
    required List<List<String>> tags,
    int? createdAt,
    void Function(NostrEvent event)? onSigned,
  }) async {
    this.tags = tags;
    final event = NostrEvent(
      id: 'accepted',
      pubkey: _me,
      createdAt: createdAt ?? 0,
      kind: kind,
      tags: tags,
      content: content,
      sig: '',
    );
    onSigned?.call(event);
    return event;
  }
}

ChannelMember _member(String pubkey) => ChannelMember(
  pubkey: pubkey,
  role: 'member',
  joinedAt: DateTime.utc(2026, 7, 26),
);

void main() {
  test(
    'DM messages tag every other participant and deduplicate mentions',
    () async {
      final relay = _FakeRelay();
      final sender = SendMessage(
        signedEventRelay: relay,
        fetchMembers: (_) async => [
          _member(_me),
          _member(_recipient),
          _member(_recipient.toUpperCase()),
        ],
        readUserCache: () => const {},
        isDirectMessage: (_) => true,
        addLocalMessage: (_, _) {},
        completeLocalMessage: (_, _) {},
        removeLocalMessage: (_, _) {},
      );

      await sender(
        channelId: 'dm-channel',
        content: 'Hello @Builder',
        mentionPubkeys: const [_recipient, _mentioned],
      );

      expect(relay.tags?.first, ['h', 'dm-channel']);
      expect(relay.tags?.where((tag) => tag.first == 'p').toList(), [
        ['p', _recipient],
        ['p', _mentioned],
      ]);
    },
  );

  test('ordinary channels keep only explicit mention tags', () async {
    final relay = _FakeRelay();
    final sender = SendMessage(
      signedEventRelay: relay,
      fetchMembers: (_) async => [_member(_recipient)],
      readUserCache: () => const {},
      isDirectMessage: (_) => false,
      addLocalMessage: (_, _) {},
      completeLocalMessage: (_, _) {},
      removeLocalMessage: (_, _) {},
    );

    await sender(
      channelId: 'general',
      content: 'Hello',
      mentionPubkeys: const [],
    );

    expect(relay.tags?.where((tag) => tag.first == 'p'), isEmpty);
  });

  test(
    'adds the signed message locally before relay acknowledgement',
    () async {
      final session = _PendingPublishRelaySession();
      final localMessages = <NostrEvent>[];
      final removedIds = <String>[];
      final completedIds = <String>[];
      final send = SendMessage(
        signedEventRelay: SignedEventRelay(
          session: session,
          nsec: nostr.Keys.generate().nsec,
        ),
        fetchMembers: (_) async => const [],
        readUserCache: () => const {},
        isDirectMessage: (_) => false,
        addLocalMessage: (_, event) => localMessages.add(event),
        completeLocalMessage: (_, eventId) => completedIds.add(eventId),
        removeLocalMessage: (_, eventId) => removedIds.add(eventId),
      );

      final result = send(channelId: _channelId, content: 'hello');
      await session.published;

      expect(localMessages, hasLength(1));
      expect(localMessages.single.id, session.event.id);
      expect(localMessages.single.content, 'hello');
      expect(localMessages.single.channelId, _channelId);
      expect(removedIds, isEmpty);

      session.accept();
      await result;
      expect(completedIds, [localMessages.single.id]);
      expect(removedIds, isEmpty);
    },
  );

  test('rolls back the signed local message when publish fails', () async {
    final session = _PendingPublishRelaySession();
    final localMessages = <NostrEvent>[];
    final completedIds = <String>[];
    final removedIds = <String>[];
    final send = SendMessage(
      signedEventRelay: SignedEventRelay(
        session: session,
        nsec: nostr.Keys.generate().nsec,
      ),
      fetchMembers: (_) async => const [],
      readUserCache: () => const {},
      isDirectMessage: (_) => false,
      addLocalMessage: (_, event) => localMessages.add(event),
      completeLocalMessage: (_, eventId) => completedIds.add(eventId),
      removeLocalMessage: (_, eventId) => removedIds.add(eventId),
    );

    final result = send(channelId: _channelId, content: 'hello');
    await session.published;
    session.reject();

    await expectLater(result, throwsException);
    expect(completedIds, isEmpty);
    expect(removedIds, [localMessages.single.id]);
  });
}

class _PendingPublishRelaySession extends RelaySessionNotifier {
  final Completer<NostrEvent> _result = Completer<NostrEvent>();
  final Completer<void> _published = Completer<void>();
  late NostrEvent event;

  Future<void> get published => _published.future;

  @override
  SessionState build() => const SessionState(status: SessionStatus.connected);

  @override
  Future<NostrEvent> publish(
    NostrEvent event, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    this.event = event;
    _published.complete();
    return _result.future;
  }

  void accept() => _result.complete(event);

  void reject() => _result.completeError(Exception('relay rejected event'));
}
