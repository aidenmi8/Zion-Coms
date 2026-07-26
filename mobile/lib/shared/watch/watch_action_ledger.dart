import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'watch_models.dart';

abstract interface class WatchActionLedgerStorage {
  Future<String?> read();

  Future<void> write(String contents);
}

class FileWatchActionLedgerStorage implements WatchActionLedgerStorage {
  final File file;

  FileWatchActionLedgerStorage(this.file);

  @override
  Future<String?> read() async {
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }
}

Future<WatchActionLedger> createApplicationSupportWatchActionLedger() async {
  final supportDirectory = await getApplicationSupportDirectory();
  return WatchActionLedger(
    storage: FileWatchActionLedgerStorage(
      File('${supportDirectory.path}/zion-watch/action-ledger.json'),
    ),
  );
}

class WatchActionLedger {
  static const _schemaVersion = 1;

  final WatchActionLedgerStorage _storage;
  final DateTime Function() _now;
  final Duration _retention;
  final int _maxEntries;
  final List<_LedgerEntry> _entries = [];
  Future<void> _gate = Future<void>.value();
  bool _loaded = false;

  WatchActionLedger({
    required WatchActionLedgerStorage storage,
    DateTime Function()? now,
    Duration retention = const Duration(days: 7),
    int maxEntries = 200,
  }) : _storage = storage,
       _now = now ?? DateTime.now,
       _retention = retention,
       _maxEntries = maxEntries;

  Future<WatchActionResult?> lookup(WatchActionRequest request) {
    return _serialized(() async {
      await _load();
      final changed = _prune();
      final matching = _entries
          .where((entry) => entry.actionId == request.actionId)
          .firstOrNull;
      if (matching == null) {
        if (changed) await _persist();
        return null;
      }
      if (!matching.matches(request)) {
        throw StateError('Watch action ID was reused for another request');
      }
      if (changed) await _persist();
      return matching.result;
    });
  }

  Future<void> record(WatchActionRequest request, WatchActionResult result) {
    return _serialized(() async {
      await _load();
      _prune();
      final existingIndex = _entries.indexWhere(
        (entry) => entry.actionId == request.actionId,
      );
      if (existingIndex >= 0 && !_entries[existingIndex].matches(request)) {
        throw StateError('Watch action ID was reused for another request');
      }
      final entry = _LedgerEntry.fromRequest(request, result, _now().toUtc());
      if (existingIndex >= 0) {
        _entries[existingIndex] = entry;
      } else {
        _entries.add(entry);
      }
      _prune();
      await _persist();
    });
  }

  Future<int> debugEntryCount() {
    return _serialized(() async {
      await _load();
      if (_prune()) await _persist();
      return _entries.length;
    });
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _gate = _gate.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final contents = await _storage.read();
    if (contents == null || contents.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _schemaVersion ||
          decoded['entries'] is! List) {
        return;
      }
      for (final value in decoded['entries'] as List) {
        if (value is Map<String, dynamic>) {
          _entries.add(_LedgerEntry.fromJson(value));
        }
      }
    } catch (_) {
      _entries.clear();
    }
  }

  bool _prune() {
    final before = _entries.length;
    final cutoff = _now().toUtc().subtract(_retention);
    _entries.removeWhere((entry) => entry.recordedAt.isBefore(cutoff));
    _entries.sort((left, right) {
      final order = right.recordedAt.compareTo(left.recordedAt);
      return order != 0 ? order : right.actionId.compareTo(left.actionId);
    });
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    return before != _entries.length;
  }

  Future<void> _persist() {
    return _storage.write(
      jsonEncode({
        'version': _schemaVersion,
        'entries': [for (final entry in _entries) entry.toJson()],
      }),
    );
  }
}

class _LedgerEntry {
  final String actionId;
  final String communityId;
  final String itemId;
  final WatchActionKind action;
  final String? targetAgentPubkey;
  final WatchActionResult result;
  final DateTime recordedAt;

  const _LedgerEntry({
    required this.actionId,
    required this.communityId,
    required this.itemId,
    required this.action,
    required this.targetAgentPubkey,
    required this.result,
    required this.recordedAt,
  });

  factory _LedgerEntry.fromRequest(
    WatchActionRequest request,
    WatchActionResult result,
    DateTime recordedAt,
  ) {
    return _LedgerEntry(
      actionId: request.actionId,
      communityId: request.communityId,
      itemId: request.itemId,
      action: request.action,
      targetAgentPubkey: request.targetAgentPubkey?.toLowerCase(),
      result: result,
      recordedAt: recordedAt,
    );
  }

  factory _LedgerEntry.fromJson(Map<String, dynamic> json) {
    return _LedgerEntry(
      actionId: json['actionID'] as String,
      communityId: json['communityID'] as String,
      itemId: json['itemID'] as String,
      action: WatchActionKind.values.firstWhere(
        (value) => value.wireName == json['action'],
      ),
      targetAgentPubkey: json['targetAgentPubkey'] as String?,
      result: WatchActionResult.fromJson(
        json['result'] as Map<String, dynamic>,
      ),
      recordedAt: DateTime.parse(json['recordedAt'] as String).toUtc(),
    );
  }

  bool matches(WatchActionRequest request) {
    return communityId == request.communityId &&
        itemId == request.itemId &&
        action == request.action &&
        targetAgentPubkey == request.targetAgentPubkey?.toLowerCase();
  }

  Map<String, dynamic> toJson() => {
    'actionID': actionId,
    'communityID': communityId,
    'itemID': itemId,
    'action': action.wireName,
    if (targetAgentPubkey != null) 'targetAgentPubkey': targetAgentPubkey,
    'result': result.toJson(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}
