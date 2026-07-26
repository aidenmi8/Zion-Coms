import 'dart:convert';

import 'package:http/http.dart' as http;

const _approvalRequestKind = 46010;
const _requiredPushKinds = {9, 1059, 40002, _approvalRequestKind};
const _registeredWakeClasses = {'default', 'time_sensitive'};
final _lowerHex64 = RegExp(r'^[0-9a-f]{64}$');

class PushExecutorKey {
  const PushExecutorKey({required this.id, required this.pubkey});

  final String id;
  final String pubkey;
}

class PushAppProfile {
  const PushAppProfile({required this.id, required this.transport});

  final String id;
  final String transport;
}

class PushDescriptor {
  const PushDescriptor({
    required this.origin,
    required this.gatewayOrigin,
    required this.executorKey,
    required this.appProfile,
    required this.pushKinds,
    required this.timeSensitiveKinds,
    required this.wakeClasses,
    required this.maxLeaseTtl,
  });

  final String origin;
  final Uri gatewayOrigin;
  final PushExecutorKey executorKey;
  final PushAppProfile appProfile;
  final Set<int> pushKinds;
  final Set<int> timeSensitiveKinds;
  final Set<String> wakeClasses;
  final Duration maxLeaseTtl;

  factory PushDescriptor.fromNip11(
    Map<String, dynamic> document, {
    required String appProfileId,
  }) {
    final extensions = _stringSet(document['supported_extensions']);
    if (!extensions.contains('nip-pl')) {
      throw const FormatException('Relay does not advertise nip-pl');
    }

    final push = _stringMap(document['push'], 'push');
    final origin = _requiredString(push, 'origin');
    final originUri = Uri.tryParse(origin);
    if (originUri == null ||
        (originUri.scheme != 'wss' && originUri.scheme != 'ws') ||
        !originUri.hasAuthority) {
      throw const FormatException('Invalid push origin');
    }

    final gatewayOrigin = Uri.tryParse(_requiredString(push, 'gateway_origin'));
    if (gatewayOrigin == null ||
        gatewayOrigin.scheme != 'https' ||
        !gatewayOrigin.hasAuthority ||
        gatewayOrigin.userInfo.isNotEmpty ||
        gatewayOrigin.path.isNotEmpty ||
        gatewayOrigin.hasQuery ||
        gatewayOrigin.hasFragment) {
      throw const FormatException('Invalid push gateway origin');
    }

    final keyObjects = _objectList(push['keys'], 'keys');
    final keyIds = <String>{};
    final currentKeys = <PushExecutorKey>[];
    for (final key in keyObjects) {
      final id = _requiredString(key, 'id');
      final pubkey = _requiredString(key, 'pubkey');
      if (!keyIds.add(id) || !_lowerHex64.hasMatch(pubkey)) {
        throw const FormatException('Invalid executor keys');
      }
      if (key['current'] == true) {
        currentKeys.add(PushExecutorKey(id: id, pubkey: pubkey));
      }
    }
    if (currentKeys.length != 1) {
      throw const FormatException('Expected exactly one current executor key');
    }

    final profileObjects = _objectList(push['app_profiles'], 'app_profiles');
    final profileIds = <String>{};
    PushAppProfile? selectedProfile;
    for (final profile in profileObjects) {
      final id = _requiredString(profile, 'id');
      final transport = _requiredString(profile, 'transport');
      if (!profileIds.add(id)) {
        throw const FormatException('Duplicate app profile');
      }
      if (id == appProfileId) {
        selectedProfile = PushAppProfile(id: id, transport: transport);
      }
    }
    if (selectedProfile == null || selectedProfile.transport != 'apns') {
      throw const FormatException('Requested APNs profile is unavailable');
    }

    final pushKinds = _intSet(push['push_kinds']);
    final timeSensitiveKinds = _intSet(push['time_sensitive_kinds']);
    if (!pushKinds.containsAll(_requiredPushKinds) ||
        !pushKinds.containsAll(timeSensitiveKinds) ||
        timeSensitiveKinds.length != 1 ||
        !timeSensitiveKinds.contains(_approvalRequestKind)) {
      throw const FormatException('Invalid push kind allowlists');
    }

    final wakeClasses = _stringSet(push['wake_classes']);
    if (wakeClasses.length != _registeredWakeClasses.length ||
        !wakeClasses.containsAll(_registeredWakeClasses)) {
      throw const FormatException('Unsupported wake classes');
    }
    final classSupport = _stringMap(push['class_support'], 'class_support');
    final transportClasses = _stringSet(classSupport['apns']);
    if (!transportClasses.containsAll(_registeredWakeClasses) ||
        !wakeClasses.containsAll(transportClasses)) {
      throw const FormatException('APNs class support is incomplete');
    }

    final limitation = _stringMap(push['limitation'], 'limitation');
    final maxLeaseTtlSeconds = limitation['max_lease_ttl'];
    if (maxLeaseTtlSeconds is! int || maxLeaseTtlSeconds <= 0) {
      throw const FormatException('Invalid max lease TTL');
    }

    return PushDescriptor(
      origin: origin,
      gatewayOrigin: gatewayOrigin,
      executorKey: currentKeys.single,
      appProfile: selectedProfile,
      pushKinds: Set.unmodifiable(pushKinds),
      timeSensitiveKinds: Set.unmodifiable(timeSensitiveKinds),
      wakeClasses: Set.unmodifiable(wakeClasses),
      maxLeaseTtl: Duration(seconds: maxLeaseTtlSeconds),
    );
  }
}

abstract interface class PushDescriptorSource {
  Future<PushDescriptor> fetch({
    required String relayBaseUrl,
    required String appProfileId,
  });
}

class HttpPushDescriptorSource implements PushDescriptorSource {
  HttpPushDescriptorSource({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<PushDescriptor> fetch({
    required String relayBaseUrl,
    required String appProfileId,
  }) async {
    final configured = Uri.parse(relayBaseUrl);
    final uri = configured.replace(
      scheme: switch (configured.scheme) {
        'wss' => 'https',
        'ws' => 'http',
        _ => configured.scheme,
      },
      path: '',
      query: null,
      fragment: null,
    );
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/nostr+json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        'Relay NIP-11 request failed (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('NIP-11 response is not an object');
    }
    return PushDescriptor.fromNip11(decoded, appProfileId: appProfileId);
  }
}

Map<String, dynamic> _stringMap(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  try {
    return value.cast<String, dynamic>();
  } on TypeError {
    throw FormatException('$field must have string keys');
  }
}

List<Map<String, dynamic>> _objectList(Object? value, String field) {
  if (value is! List || value.isEmpty) {
    throw FormatException('$field must be a non-empty array');
  }
  return value.map((entry) => _stringMap(entry, field)).toList();
}

String _requiredString(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

Set<String> _stringSet(Object? value) {
  if (value is! List || value.any((entry) => entry is! String)) {
    throw const FormatException('Expected an array of strings');
  }
  final values = value.cast<String>();
  if (values.toSet().length != values.length) {
    throw const FormatException('Duplicate string value');
  }
  return values.toSet();
}

Set<int> _intSet(Object? value) {
  if (value is! List || value.any((entry) => entry is! int)) {
    throw const FormatException('Expected an array of integers');
  }
  final values = value.cast<int>();
  if (values.isEmpty || values.toSet().length != values.length) {
    throw const FormatException('Invalid integer allowlist');
  }
  return values.toSet();
}
