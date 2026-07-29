import 'dart:convert';

import 'package:buzz/shared/apple/apple_companion_channel.dart';
import 'package:buzz/shared/watch/push_descriptor.dart';
import 'package:buzz/shared/watch/push_lease_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

const _self =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _executor =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _privateKey =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

final _descriptor = PushDescriptor(
  origin: 'wss://relay.example',
  gatewayOrigin: Uri.parse('https://push.example'),
  executorKey: const PushExecutorKey(id: 'current', pubkey: _executor),
  appProfile: const PushAppProfile(id: 'buzz-ios-sandbox', transport: 'apns'),
  pushKinds: const {9, 1059, 40002, 46010},
  timeSensitiveKinds: const {46010},
  wakeClasses: const {'default', 'time_sensitive'},
  maxLeaseTtl: const Duration(days: 30),
);

const _context = PushLeaseContext(
  communityId: 'zion',
  relayBaseUrl: 'https://relay.example',
  pubkey: _self,
  privateKeyHex: _privateKey,
  appProfileId: 'buzz-ios-sandbox',
);

class _DescriptorSource implements PushDescriptorSource {
  var calls = 0;

  @override
  Future<PushDescriptor> fetch({
    required String relayBaseUrl,
    required String appProfileId,
  }) async {
    calls++;
    return _descriptor;
  }
}

class _AppleClient implements AppleCompanionClient {
  var enableCalls = 0;
  var currentCalls = 0;
  var revokeCalls = 0;
  EndpointGrant grant;

  _AppleClient(this.grant);

  @override
  Future<EndpointGrant> enableNotifications(
    AppleEnrollmentRequest request,
  ) async {
    enableCalls++;
    return grant;
  }

  @override
  Future<EndpointGrant?> currentEndpointGrant(
    AppleEnrollmentRequest request,
  ) async {
    currentCalls++;
    return grant;
  }

  @override
  Future<AppleNotificationStatus> notificationStatus() async {
    return AppleNotificationStatus.authorized;
  }

  @override
  Future<void> revokeEndpoint(AppleEnrollmentRequest request) async {
    revokeCalls++;
  }

  @override
  Stream<int> get endpointEpochChanges => const Stream.empty();
}

class _Publisher implements PushLeasePublisher {
  final submissions = <PushLeaseSubmission>[];

  @override
  Future<void> publish(PushLeaseSubmission submission) async {
    submissions.add(submission);
  }
}

class _Encryptor {
  String? recipient;

  String call(String plaintext, String privateKeyHex, String recipientPubkey) {
    expect(privateKeyHex, _privateKey);
    recipient = recipientPubkey;
    return plaintext;
  }
}

EndpointGrant _grant({int epoch = 1, int generation = 1, DateTime? expiresAt}) {
  return EndpointGrant(
    value: 'opaque-endpoint-grant',
    appProfileId: 'buzz-ios-sandbox',
    endpointEpoch: epoch,
    generation: generation,
    expiresAt: expiresAt ?? DateTime.utc(2026, 8, 20),
  );
}

void main() {
  final now = DateTime.utc(2026, 7, 26, 12);

  test(
    'explicit enable publishes one closed lease with three subscriptions',
    () async {
      final descriptors = _DescriptorSource();
      final apple = _AppleClient(_grant());
      final publisher = _Publisher();
      final encryptor = _Encryptor();
      final store = MemoryPushLeaseStore();
      final coordinator = PushLeaseCoordinator(
        descriptorSource: descriptors,
        appleClient: apple,
        publisher: publisher,
        store: store,
        encrypt: encryptor.call,
        now: () => now,
        newLeaseId: () => 'installation-origin-id',
      );

      await coordinator.enable(_context);

      expect(coordinator.state.status, PushCompanionStatus.active);
      expect(apple.enableCalls, 1);
      expect(encryptor.recipient, _executor);
      expect(publisher.submissions, hasLength(1));
      final event = publisher.submissions.single;
      expect(event.context, _context);
      expect(event.kind, 30350);
      expect(event.tags, [
        ['d', 'installation-origin-id'],
        [
          'expiration',
          '${DateTime.utc(2026, 8, 20).millisecondsSinceEpoch ~/ 1000}',
        ],
        ['exec', 'current'],
        ['alt', 'Push lease'],
      ]);

      final body = jsonDecode(event.content) as Map<String, dynamic>;
      expect(body.keys, {
        'v',
        'origin',
        'app_profile',
        'transport',
        'endpoint',
        'generation',
        'active',
        'subscriptions',
      });
      expect(body['active'], isTrue);
      expect(body['endpoint'], 'opaque-endpoint-grant');
      expect(body['generation'], 1);
      expect(body['subscriptions'], [
        {
          'filter': {
            'kinds': [46010],
            '#p': [_self],
          },
          'class': 'time_sensitive',
        },
        {
          'filter': {
            'kinds': [9, 40002],
            '#p': [_self],
          },
          'class': 'default',
        },
        {
          'filter': {
            'kinds': [1059],
            '#p': [_self],
          },
          'class': 'default',
        },
      ]);
    },
  );

  test('restore remains idle until the user has explicitly enabled', () async {
    final descriptors = _DescriptorSource();
    final apple = _AppleClient(_grant());
    final publisher = _Publisher();
    final coordinator = PushLeaseCoordinator(
      descriptorSource: descriptors,
      appleClient: apple,
      publisher: publisher,
      store: MemoryPushLeaseStore(),
      encrypt: _Encryptor().call,
      now: () => now,
    );

    await coordinator.reconcile(_context);

    expect(coordinator.state.status, PushCompanionStatus.off);
    expect(descriptors.calls, 0);
    expect(apple.enableCalls, 0);
    expect(apple.currentCalls, 0);
    expect(publisher.submissions, isEmpty);
  });

  test(
    'endpoint epoch rotation renews the same lease at higher generation',
    () async {
      final descriptors = _DescriptorSource();
      final apple = _AppleClient(_grant());
      final publisher = _Publisher();
      final store = MemoryPushLeaseStore();
      final coordinator = PushLeaseCoordinator(
        descriptorSource: descriptors,
        appleClient: apple,
        publisher: publisher,
        store: store,
        encrypt: _Encryptor().call,
        now: () => now,
        newLeaseId: () => 'stable-id',
      );
      await coordinator.enable(_context);
      apple.grant = _grant(epoch: 2, generation: 2);

      await coordinator.reconcile(_context);

      expect(publisher.submissions, hasLength(2));
      final replacement =
          jsonDecode(publisher.submissions.last.content)
              as Map<String, dynamic>;
      expect(replacement['generation'], 2);
      expect(publisher.submissions.last.tags.first, ['d', 'stable-id']);
    },
  );

  test(
    'sign-out publishes an inactive replacement before native revocation',
    () async {
      final apple = _AppleClient(_grant());
      final publisher = _Publisher();
      final coordinator = PushLeaseCoordinator(
        descriptorSource: _DescriptorSource(),
        appleClient: apple,
        publisher: publisher,
        store: MemoryPushLeaseStore(),
        encrypt: _Encryptor().call,
        now: () => now,
        newLeaseId: () => 'stable-id',
      );
      await coordinator.enable(_context);

      await coordinator.reconcile(null);

      expect(publisher.submissions, hasLength(2));
      final tombstone =
          jsonDecode(publisher.submissions.last.content)
              as Map<String, dynamic>;
      expect(tombstone, {
        'v': 1,
        'origin': 'wss://relay.example',
        'generation': 2,
        'active': false,
      });
      expect(apple.revokeCalls, 1);
      expect(coordinator.state.status, PushCompanionStatus.off);
    },
  );
}
