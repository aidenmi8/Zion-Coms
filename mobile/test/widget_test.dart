import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buzz/app.dart';
import 'package:buzz/shared/auth/auth.dart';
import 'package:buzz/shared/branding/sentra_liquid_orbit.dart';
import 'package:buzz/shared/theme/theme_provider.dart';

void main() {
  testWidgets('App renders pairing page when unauthenticated', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          savedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const App(),
      ),
    );
    await tester.pump();
    expect(find.text('Welcome to Zion'), findsOneWidget);
  });

  testWidgets('App renders the Sentra loading treatment while auth restores', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _LoadingAuthNotifier()),
          savedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const App(),
      ),
    );
    await tester.pump();

    expect(find.byType(SentraLiquidOrbit), findsOneWidget);
    expect(find.bySemanticsLabel('Sentra'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _FakeAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async {
    return const AuthState(status: AuthStatus.unauthenticated);
  }
}

class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() => Completer<AuthState>().future;
}
