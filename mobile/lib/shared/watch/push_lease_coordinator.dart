import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:nostr/nostr.dart' as nostr;
import 'package:pointycastle/digests/sha256.dart';
import 'package:uuid/uuid.dart';

import '../apple/apple_companion_channel.dart';
import '../relay/relay_client.dart';
import 'push_descriptor.dart';

typedef PushLeaseEncryptor =
    String Function(
      String plaintext,
      String privateKeyHex,
      String recipientPubkey,
    );

enum PushCompanionStatus { off, enabling, active, needsAttention, unsupported }

class PushCompanionState {
  const PushCompanionState(this.status, {this.message});

  final PushCompanionStatus status;
  final String? message;
}

class PushLeaseContext {
  const PushLeaseContext({
    required this.communityId,
    required this.relayBaseUrl,
    required this.pubkey,
    required this.privateKeyHex,
    required this.appProfileId,
  });

  final String communityId;
  final String relayBaseUrl;
  final String pubkey;
  final String privateKeyHex;
  final String appProfileId;

  @override
  bool operator ==(Object other) {
    return other is PushLeaseContext &&
        other.communityId == communityId &&
        other.relayBaseUrl == relayBaseUrl &&
        other.pubkey == pubkey &&
        other.privateKeyHex == privateKeyHex &&
        other.appProfileId == appProfileId;
  }

  @override
  int get hashCode => Object.hash(
    communityId,
    relayBaseUrl,
    pubkey,
    privateKeyHex,
    appProfileId,
  );
}

class PushLeaseSubmission {
  const PushLeaseSubmission({
    required this.context,
    required this.kind,
    required this.content,
    required this.tags,
    required this.createdAt,
  });

  final PushLeaseContext context;
  final int kind;
  final String content;
  final List<List<String>> tags;
  final int createdAt;
}

abstract interface class PushLeasePublisher {
  Future<void> publish(PushLeaseSubmission submission);
}

class HttpPushLeasePublisher implements PushLeasePublisher {
  HttpPushLeasePublisher({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<void> publish(PushLeaseSubmission submission) async {
    final event = nostr.Event.from(
      kind: submission.kind,
      content: submission.content,
      tags: submission.tags,
      secretKey: submission.context.privateKeyHex,
      createdAt: submission.createdAt,
      verify: false,
    );
    final body = event.toJson();
    final bodyBytes = utf8.encode(body);
    final configured = Uri.parse(submission.context.relayBaseUrl);
    final base = configured.replace(
      scheme: switch (configured.scheme) {
        'wss' => 'https',
        'ws' => 'http',
        _ => configured.scheme,
      },
    );
    final url = base.resolve('/events').toString();
    final response = await _client.post(
      Uri.parse(url),
      headers: {
        'Authorization': _nip98Header(
          method: 'POST',
          url: url,
          bodyBytes: bodyBytes,
          privateKeyHex: submission.context.privateKeyHex,
        ),
        'Content-Type': 'application/json',
      },
      body: bodyBytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RelayException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['accepted'] != true) {
      final message = decoded is Map ? decoded['message'] : null;
      throw StateError(message is String ? message : 'Push lease was rejected');
    }
  }
}

class PushLeaseRecord {
  const PushLeaseRecord({
    required this.enabled,
    required this.leaseId,
    required this.generation,
    required this.endpointEpoch,
    required this.expiresAt,
  });

  final bool enabled;
  final String leaseId;
  final int generation;
  final int endpointEpoch;
  final DateTime expiresAt;

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'leaseId': leaseId,
    'generation': generation,
    'endpointEpoch': endpointEpoch,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory PushLeaseRecord.fromJson(Map<String, dynamic> json) {
    return PushLeaseRecord(
      enabled: json['enabled'] == true,
      leaseId: json['leaseId'] as String,
      generation: json['generation'] as int,
      endpointEpoch: json['endpointEpoch'] as int,
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
    );
  }
}

abstract interface class PushLeaseStore {
  Future<PushLeaseRecord?> read(String communityId);

  Future<void> write(String communityId, PushLeaseRecord record);

  Future<void> delete(String communityId);
}

class MemoryPushLeaseStore implements PushLeaseStore {
  final _records = <String, PushLeaseRecord>{};

  @override
  Future<PushLeaseRecord?> read(String communityId) async {
    return _records[communityId];
  }

  @override
  Future<void> write(String communityId, PushLeaseRecord record) async {
    _records[communityId] = record;
  }

  @override
  Future<void> delete(String communityId) async {
    _records.remove(communityId);
  }
}

class SecurePushLeaseStore implements PushLeaseStore {
  SecurePushLeaseStore({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _secureStorage = secureStorage;

  final FlutterSecureStorage _secureStorage;

  String _key(String communityId) => 'zion_push_lease_v1_$communityId';

  @override
  Future<PushLeaseRecord?> read(String communityId) async {
    final raw = await _secureStorage.read(key: _key(communityId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return PushLeaseRecord.fromJson(decoded as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String communityId, PushLeaseRecord record) {
    return _secureStorage.write(
      key: _key(communityId),
      value: jsonEncode(record.toJson()),
    );
  }

  @override
  Future<void> delete(String communityId) {
    return _secureStorage.delete(key: _key(communityId));
  }
}

class PushLeaseCoordinator {
  PushLeaseCoordinator({
    required PushDescriptorSource descriptorSource,
    required AppleCompanionClient appleClient,
    required PushLeasePublisher publisher,
    required PushLeaseStore store,
    required PushLeaseEncryptor encrypt,
    DateTime Function()? now,
    String Function()? newLeaseId,
  }) : _descriptorSource = descriptorSource,
       _appleClient = appleClient,
       _publisher = publisher,
       _store = store,
       _encrypt = encrypt,
       _now = now ?? DateTime.now,
       _newLeaseId = newLeaseId ?? _randomLeaseId;

  final PushDescriptorSource _descriptorSource;
  final AppleCompanionClient _appleClient;
  final PushLeasePublisher _publisher;
  final PushLeaseStore _store;
  final PushLeaseEncryptor _encrypt;
  final DateTime Function() _now;
  final String Function() _newLeaseId;

  PushCompanionState state = const PushCompanionState(PushCompanionStatus.off);
  PushLeaseContext? _activeContext;
  PushDescriptor? _activeDescriptor;

  Future<void> enable(PushLeaseContext context) async {
    state = const PushCompanionState(PushCompanionStatus.enabling);
    try {
      final descriptor = await _descriptorSource.fetch(
        relayBaseUrl: context.relayBaseUrl,
        appProfileId: context.appProfileId,
      );
      final expiresAt = _leaseExpiry(descriptor);
      final request = _enrollmentRequest(context, descriptor, expiresAt);
      final grant = await _appleClient.enableNotifications(request);
      await _publishActive(context, descriptor, grant);
      _activeContext = context;
      _activeDescriptor = descriptor;
      state = const PushCompanionState(PushCompanionStatus.active);
    } on AppleCompanionException catch (error) {
      state = PushCompanionState(
        error.code == 'unsupported'
            ? PushCompanionStatus.unsupported
            : PushCompanionStatus.needsAttention,
        message: error.message,
      );
    } on FormatException catch (error) {
      state = PushCompanionState(
        PushCompanionStatus.unsupported,
        message: error.message,
      );
    } on Object catch (error) {
      state = PushCompanionState(
        PushCompanionStatus.needsAttention,
        message: error.toString(),
      );
    }
  }

  /// Reconciles an already-enabled installation without ever requesting
  /// notification authorization. A null context is a sign-out boundary.
  Future<void> reconcile(PushLeaseContext? context) async {
    if (context == null) {
      await _revokeActive();
      state = const PushCompanionState(PushCompanionStatus.off);
      return;
    }

    if (_activeContext != null && _activeContext != context) {
      await _revokeActive();
    }

    final record = await _store.read(context.communityId);
    if (record == null || !record.enabled) {
      state = const PushCompanionState(PushCompanionStatus.off);
      return;
    }

    try {
      final descriptor = await _descriptorSource.fetch(
        relayBaseUrl: context.relayBaseUrl,
        appProfileId: context.appProfileId,
      );
      final request = _enrollmentRequest(
        context,
        descriptor,
        _leaseExpiry(descriptor),
      );
      final grant = await _appleClient.currentEndpointGrant(request);
      if (grant == null) {
        state = const PushCompanionState(
          PushCompanionStatus.needsAttention,
          message: 'Open Settings to restore notifications.',
        );
        return;
      }

      _activeContext = context;
      _activeDescriptor = descriptor;
      final renewalWindow = _now().toUtc().add(const Duration(days: 3));
      if (grant.endpointEpoch != record.endpointEpoch ||
          !record.expiresAt.isAfter(renewalWindow)) {
        await _publishActive(context, descriptor, grant);
      }
      state = const PushCompanionState(PushCompanionStatus.active);
    } on AppleCompanionException catch (error) {
      state = PushCompanionState(
        error.code == 'unsupported'
            ? PushCompanionStatus.unsupported
            : PushCompanionStatus.needsAttention,
        message: error.message,
      );
    } on FormatException catch (error) {
      state = PushCompanionState(
        PushCompanionStatus.unsupported,
        message: error.message,
      );
    } on Object catch (error) {
      state = PushCompanionState(
        PushCompanionStatus.needsAttention,
        message: error.toString(),
      );
    }
  }

  /// Renews after the native APNs token stream reports a rotation. This path
  /// never asks for permission: it proceeds only for an already-authorized
  /// installation that has an enabled lease record.
  Future<void> renewAfterEndpointChange(PushLeaseContext context) async {
    final record = await _store.read(context.communityId);
    if (record == null || !record.enabled) return;
    final notificationStatus = await _appleClient.notificationStatus();
    if (notificationStatus != AppleNotificationStatus.authorized &&
        notificationStatus != AppleNotificationStatus.provisional &&
        notificationStatus != AppleNotificationStatus.ephemeral) {
      state = const PushCompanionState(
        PushCompanionStatus.needsAttention,
        message: 'Allow notifications in iOS Settings.',
      );
      return;
    }
    try {
      final descriptor = await _descriptorSource.fetch(
        relayBaseUrl: context.relayBaseUrl,
        appProfileId: context.appProfileId,
      );
      final request = _enrollmentRequest(
        context,
        descriptor,
        _leaseExpiry(descriptor),
      );
      final grant = await _appleClient.enableNotifications(request);
      await _publishActive(context, descriptor, grant);
      _activeContext = context;
      _activeDescriptor = descriptor;
      state = const PushCompanionState(PushCompanionStatus.active);
    } on Object catch (error) {
      state = PushCompanionState(
        PushCompanionStatus.needsAttention,
        message: error.toString(),
      );
    }
  }

  Future<void> _publishActive(
    PushLeaseContext context,
    PushDescriptor descriptor,
    EndpointGrant grant,
  ) async {
    if (grant.appProfileId != descriptor.appProfile.id) {
      throw const FormatException('Endpoint grant profile mismatch');
    }
    final previous = await _store.read(context.communityId);
    final generation = max((previous?.generation ?? 0) + 1, grant.generation);
    final expiresAt = _earlier(
      _leaseExpiry(descriptor),
      grant.expiresAt.toUtc(),
    );
    final leaseId = previous?.leaseId ?? _newLeaseId();
    final body = <String, Object>{
      'v': 1,
      'origin': descriptor.origin,
      'app_profile': descriptor.appProfile.id,
      'transport': descriptor.appProfile.transport,
      'endpoint': grant.value,
      'generation': generation,
      'active': true,
      'subscriptions': [
        {
          'filter': {
            'kinds': [46010],
            '#p': [context.pubkey],
          },
          'class': 'time_sensitive',
        },
        {
          'filter': {
            'kinds': [9, 40002],
            '#p': [context.pubkey],
          },
          'class': 'default',
        },
        {
          'filter': {
            'kinds': [1059],
            '#p': [context.pubkey],
          },
          'class': 'default',
        },
      ],
    };
    await _publisher.publish(
      _submission(
        context: context,
        descriptor: descriptor,
        leaseId: leaseId,
        expiresAt: expiresAt,
        body: body,
      ),
    );
    await _store.write(
      context.communityId,
      PushLeaseRecord(
        enabled: true,
        leaseId: leaseId,
        generation: generation,
        endpointEpoch: grant.endpointEpoch,
        expiresAt: expiresAt,
      ),
    );
  }

  Future<void> _revokeActive() async {
    final context = _activeContext;
    final descriptor = _activeDescriptor;
    if (context == null || descriptor == null) return;
    final previous = await _store.read(context.communityId);
    if (previous == null) {
      _clearActive();
      return;
    }
    final expiresAt = _now().toUtc().add(const Duration(days: 1));
    await _publisher.publish(
      _submission(
        context: context,
        descriptor: descriptor,
        leaseId: previous.leaseId,
        expiresAt: expiresAt,
        body: {
          'v': 1,
          'origin': descriptor.origin,
          'generation': previous.generation + 1,
          'active': false,
        },
      ),
    );
    await _appleClient.revokeEndpoint(
      _enrollmentRequest(context, descriptor, expiresAt),
    );
    await _store.delete(context.communityId);
    _clearActive();
  }

  PushLeaseSubmission _submission({
    required PushLeaseContext context,
    required PushDescriptor descriptor,
    required String leaseId,
    required DateTime expiresAt,
    required Map<String, Object> body,
  }) {
    final plaintext = jsonEncode(body);
    return PushLeaseSubmission(
      context: context,
      kind: 30350,
      content: _encrypt(
        plaintext,
        context.privateKeyHex,
        descriptor.executorKey.pubkey,
      ),
      tags: [
        ['d', leaseId],
        ['expiration', '${expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000}'],
        ['exec', descriptor.executorKey.id],
        ['alt', 'Push lease'],
      ],
      createdAt: _now().toUtc().millisecondsSinceEpoch ~/ 1000,
    );
  }

  AppleEnrollmentRequest _enrollmentRequest(
    PushLeaseContext context,
    PushDescriptor descriptor,
    DateTime expiresAt,
  ) {
    return AppleEnrollmentRequest(
      gatewayOrigin: descriptor.gatewayOrigin,
      relayPubkey: context.pubkey,
      appProfileId: descriptor.appProfile.id,
      expiresAt: expiresAt,
    );
  }

  DateTime _leaseExpiry(PushDescriptor descriptor) {
    return _now().toUtc().add(descriptor.maxLeaseTtl);
  }

  void _clearActive() {
    _activeContext = null;
    _activeDescriptor = null;
  }
}

DateTime _earlier(DateTime first, DateTime second) {
  return first.isBefore(second) ? first : second;
}

String _randomLeaseId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String _nip98Header({
  required String method,
  required String url,
  required List<int> bodyBytes,
  required String privateKeyHex,
}) {
  final payloadHash = SHA256Digest()
      .process(Uint8List.fromList(bodyBytes))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  final event = nostr.Event.from(
    kind: 27235,
    content: '',
    tags: [
      ['u', url],
      ['method', method.toUpperCase()],
      ['payload', payloadHash],
      ['nonce', const Uuid().v4()],
    ],
    secretKey: privateKeyHex,
    verify: false,
  );
  return 'Nostr ${base64.encode(utf8.encode(event.toJson()))}';
}
