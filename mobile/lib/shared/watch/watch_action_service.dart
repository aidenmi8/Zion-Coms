import '../relay/nostr_models.dart';
import '../relay/signed_event_relay.dart';
import 'watch_action_ledger.dart';
import 'watch_models.dart';

typedef WatchItemLookup =
    WatchInboxItem? Function(String communityId, String itemId);

class WatchActionService {
  final SignedEventRelay _signedEventRelay;
  final WatchActionLedger _ledger;
  final String? Function() _activeCommunityId;
  final WatchItemLookup _findItem;
  final DateTime Function() _now;
  final void Function(String itemId)? _onResolved;

  WatchActionService({
    required SignedEventRelay signedEventRelay,
    required WatchActionLedger ledger,
    required String? Function() activeCommunityId,
    required WatchItemLookup findItem,
    DateTime Function()? now,
    void Function(String itemId)? onResolved,
  }) : _signedEventRelay = signedEventRelay,
       _ledger = ledger,
       _activeCommunityId = activeCommunityId,
       _findItem = findItem,
       _now = now ?? DateTime.now,
       _onResolved = onResolved;

  Future<WatchActionResult> execute(WatchActionRequest request) async {
    try {
      final replay = await _ledger.lookup(request);
      if (replay != null) return replay;
    } on StateError {
      return _result(
        request,
        WatchActionOutcome.rejected,
        'This action identifier is no longer valid.',
      );
    }

    final validation = _validate(request);
    if (validation != null) {
      await _recordTerminal(request, validation);
      return validation;
    }
    final item = _findItem(request.communityId, request.itemId)!;

    try {
      await _signedEventRelay.submit(
        kind: _commandKind(request.action),
        content: '',
        tags: _commandTags(request, item),
      );
      final result = _result(
        request,
        WatchActionOutcome.accepted,
        switch (request.action) {
          WatchActionKind.approve => 'Approved',
          WatchActionKind.deny => 'Denied',
          WatchActionKind.passToAgent => 'Passed',
          WatchActionKind.openOnPhone => 'Opened on iPhone',
        },
      );
      await _recordTerminal(request, result);
      _onResolved?.call(request.itemId);
      return result;
    } catch (error) {
      if (_isAlreadyResolved(error)) {
        final result = _result(
          request,
          WatchActionOutcome.alreadyResolved,
          'Already handled',
        );
        await _recordTerminal(request, result);
        _onResolved?.call(request.itemId);
        return result;
      }
      return _result(
        request,
        WatchActionOutcome.retryable,
        'Could not reach Zion. Try again.',
      );
    }
  }

  WatchActionResult? _validate(WatchActionRequest request) {
    if (request.schemaVersion != watchWireSchemaVersion ||
        request.communityId != _activeCommunityId()) {
      return _result(
        request,
        WatchActionOutcome.rejected,
        'This request belongs to another community.',
      );
    }
    final item = _findItem(request.communityId, request.itemId);
    if (item == null ||
        item.communityId != request.communityId ||
        item.kind != WatchItemKind.approval) {
      return _result(
        request,
        WatchActionOutcome.alreadyResolved,
        'Already handled',
      );
    }
    if (item.expiresAt == null || !item.expiresAt!.isAfter(_now().toUtc())) {
      return _result(
        request,
        WatchActionOutcome.alreadyResolved,
        'This approval has expired.',
      );
    }
    if (!item.allowedActions.contains(request.action) ||
        request.action == WatchActionKind.openOnPhone ||
        !_isHex(item.approvalDigest, 64)) {
      return _result(
        request,
        WatchActionOutcome.rejected,
        'This action is not available.',
      );
    }
    if (request.action == WatchActionKind.passToAgent) {
      final target = request.targetAgentPubkey?.toLowerCase();
      if (!_isHex(target, 64) ||
          !item.eligibleAgents.any(
            (candidate) => candidate.pubkey.toLowerCase() == target,
          ) ||
          item.channelId == null ||
          !_isHex(item.sourceEventId, 64)) {
        return _result(
          request,
          WatchActionOutcome.rejected,
          'That agent is no longer available.',
        );
      }
    } else if (request.targetAgentPubkey != null) {
      return _result(
        request,
        WatchActionOutcome.rejected,
        'Unexpected destination agent.',
      );
    }
    return null;
  }

  int _commandKind(WatchActionKind action) => switch (action) {
    WatchActionKind.approve => EventKind.workflowApprovalGrantCommand,
    WatchActionKind.deny => EventKind.workflowApprovalDenyCommand,
    WatchActionKind.passToAgent => EventKind.workflowApprovalPassCommand,
    WatchActionKind.openOnPhone => throw StateError('not a relay action'),
  };

  List<List<String>> _commandTags(
    WatchActionRequest request,
    WatchInboxItem item,
  ) {
    final tags = <List<String>>[
      ['d', item.approvalDigest!],
    ];
    if (request.action == WatchActionKind.passToAgent) {
      tags.addAll([
        ['p', request.targetAgentPubkey!.toLowerCase()],
        ['e', item.sourceEventId],
        ['h', item.channelId!],
      ]);
    }
    return tags;
  }

  WatchActionResult _result(
    WatchActionRequest request,
    WatchActionOutcome outcome,
    String message,
  ) {
    return WatchActionResult(
      actionId: request.actionId,
      communityId: request.communityId,
      itemId: request.itemId,
      outcome: outcome,
      message: message,
      resolvedAt: _now().toUtc(),
    );
  }

  Future<void> _recordTerminal(
    WatchActionRequest request,
    WatchActionResult result,
  ) {
    return _ledger.record(request, result);
  }
}

bool _isHex(String? value, int length) {
  return value != null &&
      value.length == length &&
      RegExp('^[0-9a-fA-F]{$length}\$').hasMatch(value);
}

bool _isAlreadyResolved(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('already handled') ||
      message.contains('not pending') ||
      message.contains('stale') ||
      message.contains('expired') ||
      message.contains('conflict');
}
