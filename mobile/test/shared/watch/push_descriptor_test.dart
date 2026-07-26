import 'package:buzz/shared/watch/push_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

const _executor =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _nip11({
  String gatewayOrigin = 'https://push.example',
  List<Map<String, dynamic>>? keys,
  List<Map<String, dynamic>>? appProfiles,
  List<int> timeSensitiveKinds = const [46010],
}) {
  return {
    'supported_extensions': ['nip-pl'],
    'push': {
      'origin': 'wss://relay.example',
      'gateway_origin': gatewayOrigin,
      'keys':
          keys ??
          [
            {'id': '2026-07', 'pubkey': _executor, 'current': true},
          ],
      'app_profiles':
          appProfiles ??
          [
            {'id': 'buzz-ios-production', 'transport': 'apns'},
            {'id': 'buzz-ios-sandbox', 'transport': 'apns'},
          ],
      'push_kinds': [9, 1059, 40002, 46010],
      'time_sensitive_kinds': timeSensitiveKinds,
      'wake_classes': ['default', 'time_sensitive'],
      'class_support': {
        'apns': ['default', 'time_sensitive'],
      },
      'limitation': {'max_lease_ttl': 2592000},
    },
  };
}

void main() {
  test('parses the current executor and selected APNs profile', () {
    final descriptor = PushDescriptor.fromNip11(
      _nip11(),
      appProfileId: 'buzz-ios-sandbox',
    );

    expect(descriptor.origin, 'wss://relay.example');
    expect(descriptor.gatewayOrigin, Uri.parse('https://push.example'));
    expect(descriptor.executorKey.id, '2026-07');
    expect(descriptor.executorKey.pubkey, _executor);
    expect(descriptor.appProfile.id, 'buzz-ios-sandbox');
    expect(descriptor.appProfile.transport, 'apns');
    expect(descriptor.pushKinds, {9, 1059, 40002, 46010});
    expect(descriptor.timeSensitiveKinds, {46010});
    expect(descriptor.maxLeaseTtl, const Duration(days: 30));
  });

  test('rejects a non-HTTPS gateway origin', () {
    expect(
      () => PushDescriptor.fromNip11(
        _nip11(gatewayOrigin: 'http://push.example'),
        appProfileId: 'buzz-ios-production',
      ),
      throwsFormatException,
    );
  });

  test('rejects an unknown app profile', () {
    expect(
      () => PushDescriptor.fromNip11(
        _nip11(),
        appProfileId: 'unknown-ios-profile',
      ),
      throwsFormatException,
    );
  });

  test('rejects a descriptor without exactly one current executor key', () {
    expect(
      () => PushDescriptor.fromNip11(
        _nip11(
          keys: [
            {'id': 'old', 'pubkey': _executor, 'retiring': true},
          ],
        ),
        appProfileId: 'buzz-ios-production',
      ),
      throwsFormatException,
    );
  });

  test('rejects time-sensitive delivery for a non-approval kind', () {
    expect(
      () => PushDescriptor.fromNip11(
        _nip11(timeSensitiveKinds: [9, 46010]),
        appProfileId: 'buzz-ios-production',
      ),
      throwsFormatException,
    );
  });
}
