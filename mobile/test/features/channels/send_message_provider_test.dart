import 'package:buzz/features/channels/channel_management_provider.dart';
import 'package:buzz/features/channels/send_message_provider.dart';
import 'package:buzz/shared/relay/nostr_models.dart';
import 'package:buzz/shared/relay/signed_event_relay.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _recipient =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _mentioned =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

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
  }) async {
    this.tags = tags;
    return const NostrEvent(
      id: 'accepted',
      pubkey: '',
      createdAt: 0,
      kind: 0,
      tags: [],
      content: '',
      sig: '',
    );
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
    );

    await sender(
      channelId: 'general',
      content: 'Hello',
      mentionPubkeys: const [],
    );

    expect(relay.tags?.where((tag) => tag.first == 'p'), isEmpty);
  });
}
