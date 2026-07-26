import 'dart:async';

import 'package:buzz/app/watch_companion_coordinator.dart';
import 'package:buzz/shared/apple/apple_companion_channel.dart';
import 'package:buzz/shared/watch/watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWatchBridge implements AppleWatchBridgeClient {
  final actions = StreamController<WatchActionRequest>.broadcast();
  final snapshots = <WatchInboxSnapshot>[];
  final results = <WatchActionResult>[];
  var clearCount = 0;

  @override
  Future<void> clearWatchSnapshot() async {
    clearCount += 1;
  }

  @override
  Future<void> completeWatchAction(WatchActionResult result) async {
    results.add(result);
  }

  @override
  Future<void> publishWatchSnapshot(WatchInboxSnapshot snapshot) async {
    snapshots.add(snapshot);
  }

  @override
  Stream<WatchActionRequest> watchActions() => actions.stream;

  Future<void> dispose() => actions.close();
}

void main() {
  const request = WatchActionRequest(
    actionId: '10000000-0000-4000-8000-000000000001',
    communityId: 'zion',
    itemId: 'approval-1',
    action: WatchActionKind.approve,
  );
  final snapshot = WatchInboxSnapshot(
    communityId: 'zion',
    communityName: 'Zion',
    generatedAt: DateTime.utc(2026, 7, 26, 12),
    items: const [],
  );

  test('parses native action wire data', () {
    expect(
      WatchActionRequest.fromWireJson({
        'version': 1,
        'actionID': request.actionId,
        'communityID': 'zion',
        'itemID': 'approval-1',
        'action': 'approve',
      }).toWireJson(),
      request.toWireJson(),
    );
  });

  test('publishes active snapshots and clears signed-out state', () async {
    final bridge = _FakeWatchBridge();
    final coordinator = WatchPhoneBridgeCoordinator(
      bridge: bridge,
      execute: (_) async => throw UnimplementedError(),
    );

    await coordinator.publish(snapshot);
    await coordinator.publish(null);

    expect(bridge.snapshots, [snapshot]);
    expect(bridge.clearCount, 1);
    await coordinator.dispose();
    await bridge.dispose();
  });

  test(
    'routes watch actions to the phone service and returns results',
    () async {
      final bridge = _FakeWatchBridge();
      final result = WatchActionResult(
        actionId: request.actionId,
        communityId: request.communityId,
        itemId: request.itemId,
        outcome: WatchActionOutcome.accepted,
        message: 'Approved',
        resolvedAt: DateTime.utc(2026, 7, 26, 12, 1),
      );
      final executed = <WatchActionRequest>[];
      final coordinator = WatchPhoneBridgeCoordinator(
        bridge: bridge,
        execute: (action) async {
          executed.add(action);
          return result;
        },
      );
      coordinator.start();

      bridge.actions.add(request);
      await pumpEventQueue();

      expect(executed, [request]);
      expect(bridge.results, [result]);
      await coordinator.dispose();
      await bridge.dispose();
    },
  );
}
