import 'package:buzz/shared/watch/watch_action_ledger.dart';
import 'package:buzz/shared/watch/watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryLedgerStorage implements WatchActionLedgerStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String contents) async {
    value = contents;
  }
}

WatchActionRequest _request(int index) => WatchActionRequest(
  actionId: 'action-$index',
  communityId: 'zion',
  itemId: 'item-$index',
  action: WatchActionKind.approve,
);

WatchActionResult _result(int index, DateTime resolvedAt) => WatchActionResult(
  actionId: 'action-$index',
  communityId: 'zion',
  itemId: 'item-$index',
  outcome: WatchActionOutcome.accepted,
  message: 'Approved',
  resolvedAt: resolvedAt,
);

void main() {
  test('persists and replays a result for the same action envelope', () async {
    final storage = _MemoryLedgerStorage();
    final ledger = WatchActionLedger(storage: storage);
    final request = _request(1);
    final result = _result(1, DateTime.utc(2026, 7, 26));

    await ledger.record(request, result);

    expect(
      (await ledger.lookup(request))?.outcome,
      WatchActionOutcome.accepted,
    );
    final reloaded = WatchActionLedger(storage: storage);
    expect((await reloaded.lookup(request))?.message, 'Approved');
  });

  test('rejects reuse of an action ID for a different item', () async {
    final ledger = WatchActionLedger(storage: _MemoryLedgerStorage());
    final request = _request(1);
    await ledger.record(request, _result(1, DateTime.utc(2026, 7, 26)));

    final collision = WatchActionRequest(
      actionId: request.actionId,
      communityId: request.communityId,
      itemId: 'different-item',
      action: request.action,
    );
    await expectLater(ledger.lookup(collision), throwsStateError);
  });

  test('expires entries after seven days and caps storage at 200', () async {
    final storage = _MemoryLedgerStorage();
    var clock = DateTime.utc(2026, 7, 26, 12);
    final ledger = WatchActionLedger(storage: storage, now: () => clock);

    for (var index = 0; index < 205; index++) {
      await ledger.record(_request(index), _result(index, clock));
      clock = clock.add(const Duration(seconds: 1));
    }

    expect(await ledger.debugEntryCount(), 200);
    expect(await ledger.lookup(_request(0)), isNull);
    expect(await ledger.lookup(_request(204)), isNotNull);

    clock = clock.add(const Duration(days: 8));
    expect(await ledger.lookup(_request(204)), isNull);
    expect(await ledger.debugEntryCount(), 0);
  });
}
