import 'package:flutter/foundation.dart';

const watchWireSchemaVersion = 1;

enum WatchItemKind { approval, directMessage, mention }

enum WatchActionKind { approve, deny, passToAgent, openOnPhone }

enum WatchActionState { queued, sending, succeeded, failed }

enum WatchActionOutcome { accepted, alreadyResolved, rejected, retryable }

enum WatchAgentAvailability { online, away }

extension WatchItemKindWire on WatchItemKind {
  String get wireName => switch (this) {
    WatchItemKind.approval => 'approval',
    WatchItemKind.directMessage => 'directMessage',
    WatchItemKind.mention => 'mention',
  };
}

extension WatchActionKindWire on WatchActionKind {
  String get wireName => switch (this) {
    WatchActionKind.approve => 'approve',
    WatchActionKind.deny => 'deny',
    WatchActionKind.passToAgent => 'pass',
    WatchActionKind.openOnPhone => 'openOnPhone',
  };
}

extension WatchActionOutcomeWire on WatchActionOutcome {
  String get wireName => switch (this) {
    WatchActionOutcome.accepted => 'accepted',
    WatchActionOutcome.alreadyResolved => 'alreadyResolved',
    WatchActionOutcome.rejected => 'rejected',
    WatchActionOutcome.retryable => 'retryable',
  };
}

@immutable
class WatchAgentSummary {
  final String pubkey;
  final String displayName;
  final WatchAgentAvailability availability;
  final int sortRank;

  const WatchAgentSummary({
    required this.pubkey,
    required this.displayName,
    required this.availability,
    required this.sortRank,
  });

  Map<String, dynamic> toWireJson() => {
    'pubkey': pubkey,
    'displayName': displayName,
    'availability': availability.name,
    'sortRank': sortRank,
  };
}

@immutable
class WatchInboxItem {
  final String itemId;
  final WatchItemKind kind;
  final String communityId;
  final String? channelId;
  final String title;
  final String senderLabel;
  final String? channelLabel;
  final String body;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String sourceEventId;
  final bool isTruncated;
  final Set<WatchActionKind> allowedActions;
  final List<WatchAgentSummary> eligibleAgents;

  /// Phone-only approval reference. Never included in [toWireJson].
  final String? approvalDigest;

  /// Phone-only identity used to validate Pass candidates.
  final String? requestingAgentPubkey;

  const WatchInboxItem({
    required this.itemId,
    required this.kind,
    required this.communityId,
    required this.channelId,
    required this.title,
    required this.senderLabel,
    required this.channelLabel,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    required this.sourceEventId,
    required this.isTruncated,
    required this.allowedActions,
    this.eligibleAgents = const [],
    this.approvalDigest,
    this.requestingAgentPubkey,
  });

  Map<String, dynamic> toWireJson() => {
    'itemID': itemId,
    'type': kind.wireName,
    'communityID': communityId,
    if (channelId != null) 'channelID': channelId,
    'title': title,
    'senderLabel': senderLabel,
    if (channelLabel != null) 'channelLabel': channelLabel,
    'body': body,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    'sourceEventID': sourceEventId,
    'isTruncated': isTruncated,
    'allowedActions': [
      for (final action
          in (allowedActions.toList()
            ..sort((left, right) => left.index.compareTo(right.index))))
        action.wireName,
    ],
    'eligibleAgents': [for (final agent in eligibleAgents) agent.toWireJson()],
  };
}

@immutable
class WatchInboxSnapshot {
  final int schemaVersion;
  final String communityId;
  final String communityName;
  final DateTime generatedAt;
  final List<WatchInboxItem> items;

  const WatchInboxSnapshot({
    this.schemaVersion = watchWireSchemaVersion,
    required this.communityId,
    required this.communityName,
    required this.generatedAt,
    required this.items,
  });

  Map<String, dynamic> toWireJson() => {
    'version': schemaVersion,
    'communityID': communityId,
    'communityName': communityName,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'items': [for (final item in items) item.toWireJson()],
  };
}

@immutable
class WatchActionRequest {
  final int schemaVersion;
  final String actionId;
  final String communityId;
  final String itemId;
  final WatchActionKind action;
  final String? targetAgentPubkey;

  const WatchActionRequest({
    this.schemaVersion = watchWireSchemaVersion,
    required this.actionId,
    required this.communityId,
    required this.itemId,
    required this.action,
    this.targetAgentPubkey,
  });

  Map<String, dynamic> toWireJson() => {
    'version': schemaVersion,
    'actionID': actionId,
    'communityID': communityId,
    'itemID': itemId,
    'action': action.wireName,
    if (targetAgentPubkey != null) 'targetAgentPubkey': targetAgentPubkey,
  };

  factory WatchActionRequest.fromWireJson(Map<Object?, Object?> json) {
    final version = json['version'];
    final actionId = json['actionID'];
    final communityId = json['communityID'];
    final itemId = json['itemID'];
    final actionName = json['action'];
    final targetAgentPubkey = json['targetAgentPubkey'];
    final action = switch (actionName) {
      'approve' => WatchActionKind.approve,
      'deny' => WatchActionKind.deny,
      'pass' => WatchActionKind.passToAgent,
      'openOnPhone' => WatchActionKind.openOnPhone,
      _ => null,
    };
    if (version is! int ||
        version != watchWireSchemaVersion ||
        actionId is! String ||
        actionId.isEmpty ||
        communityId is! String ||
        communityId.isEmpty ||
        itemId is! String ||
        itemId.isEmpty ||
        action == null ||
        (targetAgentPubkey != null && targetAgentPubkey is! String) ||
        (action == WatchActionKind.passToAgent &&
            (targetAgentPubkey is! String || targetAgentPubkey.isEmpty)) ||
        (action != WatchActionKind.passToAgent && targetAgentPubkey != null)) {
      throw const FormatException('Invalid watch action request');
    }
    return WatchActionRequest(
      schemaVersion: version,
      actionId: actionId,
      communityId: communityId,
      itemId: itemId,
      action: action,
      targetAgentPubkey: targetAgentPubkey as String?,
    );
  }
}

@immutable
class WatchActionResult {
  final int schemaVersion;
  final String actionId;
  final String communityId;
  final String itemId;
  final WatchActionOutcome outcome;
  final String message;
  final DateTime resolvedAt;

  const WatchActionResult({
    this.schemaVersion = watchWireSchemaVersion,
    required this.actionId,
    required this.communityId,
    required this.itemId,
    required this.outcome,
    required this.message,
    required this.resolvedAt,
  });

  Map<String, dynamic> toWireJson() => {
    'version': schemaVersion,
    'actionID': actionId,
    'communityID': communityId,
    'itemID': itemId,
    'outcome': outcome.wireName,
    'message': message,
    'resolvedAt': resolvedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toJson() => toWireJson();

  factory WatchActionResult.fromJson(Map<String, dynamic> json) {
    return WatchActionResult(
      schemaVersion: json['version'] as int,
      actionId: json['actionID'] as String,
      communityId: json['communityID'] as String,
      itemId: json['itemID'] as String,
      outcome: WatchActionOutcome.values.firstWhere(
        (value) => value.wireName == json['outcome'],
      ),
      message: json['message'] as String,
      resolvedAt: DateTime.parse(json['resolvedAt'] as String).toUtc(),
    );
  }
}
