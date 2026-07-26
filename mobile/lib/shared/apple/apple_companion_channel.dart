import 'package:flutter/services.dart';

import '../watch/watch_models.dart';

enum AppleNotificationStatus {
  unsupported,
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral;

  static AppleNotificationStatus fromWire(String value) {
    return switch (value) {
      'not_determined' => notDetermined,
      'denied' => denied,
      'authorized' => authorized,
      'provisional' => provisional,
      'ephemeral' => ephemeral,
      _ => unsupported,
    };
  }
}

class AppleEnrollmentRequest {
  const AppleEnrollmentRequest({
    required this.gatewayOrigin,
    required this.relayPubkey,
    required this.appProfileId,
    required this.expiresAt,
  });

  final Uri gatewayOrigin;
  final String relayPubkey;
  final String appProfileId;
  final DateTime expiresAt;

  Map<String, Object> toWireJson() => {
    'gatewayOrigin': gatewayOrigin.toString(),
    'relayPubkey': relayPubkey,
    'appProfileId': appProfileId,
    'expiresAt': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
  };
}

class EndpointGrant {
  const EndpointGrant({
    required this.value,
    required this.appProfileId,
    required this.endpointEpoch,
    required this.generation,
    required this.expiresAt,
  });

  final String value;
  final String appProfileId;
  final int endpointEpoch;
  final int generation;
  final DateTime expiresAt;

  factory EndpointGrant.fromWireJson(Map<Object?, Object?> json) {
    final value = json['endpointGrant'];
    final profile = json['appProfileId'];
    final epoch = json['endpointEpoch'];
    final generation = json['generation'];
    final expiresAt = json['expiresAt'];
    if (value is! String ||
        value.isEmpty ||
        profile is! String ||
        profile.isEmpty ||
        epoch is! int ||
        epoch <= 0 ||
        generation is! int ||
        generation <= 0 ||
        expiresAt is! int) {
      throw const FormatException('Invalid endpoint grant');
    }
    return EndpointGrant(
      value: value,
      appProfileId: profile,
      endpointEpoch: epoch,
      generation: generation,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
        isUtc: true,
      ),
    );
  }
}

class AppleCompanionException implements Exception {
  const AppleCompanionException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message == null ? code : '$code: $message';
}

abstract interface class AppleCompanionClient {
  Future<AppleNotificationStatus> notificationStatus();

  Future<EndpointGrant> enableNotifications(AppleEnrollmentRequest request);

  Future<EndpointGrant?> currentEndpointGrant(AppleEnrollmentRequest request);

  Future<void> revokeEndpoint(AppleEnrollmentRequest request);

  Stream<int> get endpointEpochChanges;
}

abstract interface class AppleWatchBridgeClient {
  Future<void> publishWatchSnapshot(WatchInboxSnapshot snapshot);

  Future<void> clearWatchSnapshot();

  Stream<WatchActionRequest> watchActions();

  Future<void> completeWatchAction(WatchActionResult result);
}

class AppleCompanionChannel
    implements AppleCompanionClient, AppleWatchBridgeClient {
  AppleCompanionChannel({
    MethodChannel methodChannel = const MethodChannel('zion/apple_companion'),
    EventChannel eventChannel = const EventChannel(
      'zion/apple_companion/events',
    ),
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  late final Stream<Map<Object?, Object?>> _events = _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<Object?, Object?>.from(event as Map))
      .asBroadcastStream();

  @override
  Future<AppleNotificationStatus> notificationStatus() async {
    try {
      final status = await _methodChannel.invokeMethod<String>(
        'notificationStatus',
      );
      return AppleNotificationStatus.fromWire(status ?? 'unsupported');
    } on MissingPluginException {
      return AppleNotificationStatus.unsupported;
    }
  }

  @override
  Future<EndpointGrant> enableNotifications(
    AppleEnrollmentRequest request,
  ) async {
    final result = await _invokeGrant(
      'enableNotifications',
      request.toWireJson(),
    );
    if (result == null) {
      throw const AppleCompanionException(
        'not_ready',
        'No endpoint grant is available.',
      );
    }
    return result;
  }

  @override
  Future<EndpointGrant?> currentEndpointGrant(AppleEnrollmentRequest request) {
    return _invokeGrant('currentEndpointGrant', request.toWireJson());
  }

  @override
  Future<void> revokeEndpoint(AppleEnrollmentRequest request) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'revokeEndpoint',
        request.toWireJson(),
      );
    } on PlatformException catch (error) {
      throw AppleCompanionException(error.code, error.message);
    } on MissingPluginException {
      throw const AppleCompanionException('unsupported');
    }
  }

  @override
  Stream<int> get endpointEpochChanges => _events
      .map((event) => event['endpointEpoch'])
      .where((epoch) => epoch is int)
      .cast<int>();

  @override
  Future<void> publishWatchSnapshot(WatchInboxSnapshot snapshot) {
    return _invokeWatchMethod('publishWatchSnapshot', snapshot.toWireJson());
  }

  @override
  Future<void> clearWatchSnapshot() {
    return _invokeWatchMethod('clearWatchSnapshot');
  }

  @override
  Stream<WatchActionRequest> watchActions() => _events
      .map((event) => event['watchAction'])
      .where((action) => action is Map)
      .map(
        (action) => WatchActionRequest.fromWireJson(
          Map<Object?, Object?>.from(action as Map),
        ),
      );

  @override
  Future<void> completeWatchAction(WatchActionResult result) {
    return _invokeWatchMethod('completeWatchAction', result.toWireJson());
  }

  Future<EndpointGrant?> _invokeGrant(
    String method,
    Map<String, Object> arguments,
  ) async {
    try {
      final value = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
        method,
        arguments,
      );
      return value == null ? null : EndpointGrant.fromWireJson(value);
    } on PlatformException catch (error) {
      throw AppleCompanionException(error.code, error.message);
    } on MissingPluginException {
      throw const AppleCompanionException('unsupported');
    }
  }

  Future<void> _invokeWatchMethod(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      await _methodChannel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw AppleCompanionException(error.code, error.message);
    } on MissingPluginException {
      throw const AppleCompanionException('unsupported');
    }
  }
}

const bool _isProfileMode = bool.fromEnvironment('dart.vm.profile');
const bool _isReleaseMode = bool.fromEnvironment('dart.vm.product');
const String applePushAppProfileId = _isProfileMode || _isReleaseMode
    ? 'buzz-ios-production'
    : 'buzz-ios-sandbox';
