import 'package:buzz/features/channels/thread_replies_provider.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test(
    'falls back to WebSocket history when the thread bridge query fails',
    () async {
      final relaySession = _ThreadRelaySession(historyEvents: [_reply]);
      final container = ProviderContainer(
        overrides: [relaySessionProvider.overrideWith(() => relaySession)],
      );
      addTearDown(container.dispose);

      final replies = await container.read(
        threadRepliesProvider(
          const ThreadRepliesArgs(channelId: _channelId, rootId: _rootId),
        ).future,
      );

      expect(replies.map((event) => event.id), ['reply']);
      expect(relaySession.queryFilters, hasLength(1));
      expect(relaySession.historyFilters, hasLength(1));
      expect(relaySession.historyFilters.single.tags, {
        '#e': [_rootId],
        '#h': [_channelId],
      });
      expect(relaySession.historyFilters.single.extensions, isEmpty);
    },
  );

  test(
    'falls back to WebSocket history when the thread bridge returns empty',
    () async {
      final relaySession = _ThreadRelaySession(
        historyEvents: [_reply],
        queryEvents: const [],
      );
      final container = ProviderContainer(
        overrides: [relaySessionProvider.overrideWith(() => relaySession)],
      );
      addTearDown(container.dispose);

      final replies = await container.read(
        threadRepliesProvider(
          const ThreadRepliesArgs(channelId: _channelId, rootId: _rootId),
        ).future,
      );

      expect(replies.map((event) => event.id), ['reply']);
      expect(relaySession.queryFilters, hasLength(1));
      expect(relaySession.historyFilters, hasLength(1));
    },
  );
}

const _channelId = '11111111-1111-4111-8111-111111111111';
const _rootId = 'root';

const _reply = NostrEvent(
  id: 'reply',
  pubkey: 'agent',
  createdAt: 17,
  kind: EventKind.streamMessage,
  tags: [
    ['h', _channelId],
    ['e', _rootId, '', 'reply'],
  ],
  content: 'Alert',
  sig: 'sig',
);

class _ThreadRelaySession extends RelaySessionNotifier {
  final List<NostrEvent> historyEvents;
  final List<NostrEvent>? queryEvents;
  final List<NostrFilter> queryFilters = [];
  final List<NostrFilter> historyFilters = [];

  _ThreadRelaySession({required this.historyEvents, this.queryEvents});

  @override
  SessionState build() => const SessionState(status: SessionStatus.connected);

  @override
  Future<List<NostrEvent>> queryRelay(
    List<NostrFilter> filters, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    queryFilters.addAll(filters);
    if (queryEvents != null) return queryEvents!;
    throw Exception('thread bridge unavailable');
  }

  @override
  Future<List<NostrEvent>> fetchHistory(
    NostrFilter filter, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    historyFilters.add(filter);
    return historyEvents;
  }
}
