import '../relay/nostr_models.dart';
import 'watch_models.dart';

class WatchInboxSource {
  final String communityId;
  final NostrEvent event;
  final String senderLabel;
  final String? channelLabel;
  final bool isDirectMessage;

  const WatchInboxSource({
    required this.communityId,
    required this.event,
    required this.senderLabel,
    required this.channelLabel,
    this.isDirectMessage = false,
  });
}

class WatchInboxMapper {
  final int maxItems;
  final int maxBodyScalars;

  const WatchInboxMapper({this.maxItems = 20, this.maxBodyScalars = 2000});

  WatchInboxSnapshot map({
    required String communityId,
    required String communityName,
    required String currentPubkey,
    required Iterable<WatchInboxSource> sources,
    Map<String, List<WatchAgentSummary>> eligibleAgentsByApprovalDigest =
        const {},
    DateTime? now,
  }) {
    final generatedAt = (now ?? DateTime.now()).toUtc();
    final current = currentPubkey.toLowerCase();
    final scoped = [
      for (final source in sources)
        if (source.communityId == communityId) source,
    ];
    final resolvedApprovalDigests = <String>{
      for (final source in scoped)
        if (_isTerminalApproval(source.event.kind))
          ?source.event.getTagValue('d'),
    };
    final items = <WatchInboxItem>[];

    for (final source in scoped) {
      final event = source.event;
      final hasSelfTag = event.tags.any(
        (tag) =>
            tag.length >= 2 && tag[0] == 'p' && tag[1].toLowerCase() == current,
      );
      if (event.kind == EventKind.workflowApprovalRequested) {
        final digest = event.getTagValue('d');
        final expirySeconds = int.tryParse(
          event.getTagValue('expiration') ?? '',
        );
        final expiresAt = expirySeconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                expirySeconds * 1000,
                isUtc: true,
              );
        if (!hasSelfTag ||
            digest == null ||
            !_isHexDigest(digest) ||
            resolvedApprovalDigests.contains(digest) ||
            expiresAt == null ||
            !expiresAt.isAfter(generatedAt)) {
          continue;
        }
        final agents = eligibleAgentsByApprovalDigest[digest] ?? const [];
        final preview = _preview(event.content);
        items.add(
          WatchInboxItem(
            itemId: event.id,
            kind: WatchItemKind.approval,
            communityId: communityId,
            channelId: event.channelId,
            title: 'Approval requested',
            senderLabel: source.senderLabel,
            channelLabel: source.channelLabel,
            body: preview.text,
            createdAt: _eventTime(event),
            expiresAt: expiresAt,
            sourceEventId: event.id,
            isTruncated: preview.truncated,
            allowedActions: {
              WatchActionKind.approve,
              WatchActionKind.deny,
              if (agents.isNotEmpty) WatchActionKind.passToAgent,
              WatchActionKind.openOnPhone,
            },
            eligibleAgents: List.unmodifiable(agents),
            approvalDigest: digest.toLowerCase(),
            requestingAgentPubkey: event.getTagValue('agent')?.toLowerCase(),
          ),
        );
        continue;
      }

      if (event.pubkey.toLowerCase() == current) continue;
      final WatchItemKind? kind;
      if (source.isDirectMessage &&
          hasSelfTag &&
          event.kind == EventKind.streamMessage) {
        kind = WatchItemKind.directMessage;
      } else if (hasSelfTag &&
          (event.kind == EventKind.streamMessage ||
              event.kind == EventKind.streamMessageV2)) {
        kind = WatchItemKind.mention;
      } else {
        kind = null;
      }
      if (kind == null) continue;
      final preview = _preview(event.content);
      items.add(
        WatchInboxItem(
          itemId: event.id,
          kind: kind,
          communityId: communityId,
          channelId: event.channelId,
          title: kind == WatchItemKind.directMessage
              ? 'Direct message'
              : 'Mention',
          senderLabel: source.senderLabel,
          channelLabel: source.channelLabel,
          body: preview.text,
          createdAt: _eventTime(event),
          expiresAt: null,
          sourceEventId: event.id,
          isTruncated: preview.truncated,
          allowedActions: const {WatchActionKind.openOnPhone},
        ),
      );
    }

    items.sort((left, right) {
      final kindOrder = _kindRank(left.kind).compareTo(_kindRank(right.kind));
      if (kindOrder != 0) return kindOrder;
      final timeOrder = right.createdAt.compareTo(left.createdAt);
      return timeOrder != 0 ? timeOrder : left.itemId.compareTo(right.itemId);
    });
    return WatchInboxSnapshot(
      communityId: communityId,
      communityName: communityName,
      generatedAt: generatedAt,
      items: List.unmodifiable(items.take(maxItems)),
    );
  }

  ({String text, bool truncated}) _preview(String source) {
    final withoutMedia = source
        .replaceAllMapped(
          RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]+\)'),
          (match) => match.group(1) ?? '',
        );
    final plain = withoutMedia
        .replaceAll(RegExp(r'[`*_>#~]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final runes = plain.runes.toList(growable: false);
    if (runes.length <= maxBodyScalars) {
      return (text: plain, truncated: false);
    }
    return (
      text: String.fromCharCodes(runes.take(maxBodyScalars)),
      truncated: true,
    );
  }
}

bool _isTerminalApproval(int kind) {
  return kind == EventKind.workflowApprovalGranted ||
      kind == EventKind.workflowApprovalDenied ||
      kind == EventKind.workflowApprovalDelegated;
}

bool _isHexDigest(String value) {
  return value.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
}

DateTime _eventTime(NostrEvent event) {
  return DateTime.fromMillisecondsSinceEpoch(
    event.createdAt * 1000,
    isUtc: true,
  );
}

int _kindRank(WatchItemKind kind) => switch (kind) {
  WatchItemKind.approval => 0,
  WatchItemKind.directMessage || WatchItemKind.mention => 1,
};
