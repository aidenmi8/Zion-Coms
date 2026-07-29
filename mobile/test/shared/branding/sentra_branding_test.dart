import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buzz/shared/branding/sentra_branding.dart';

void main() {
  test('uses the white Sentra lockup on dark surfaces', () {
    expect(sentraWordmarkAssetFor(Brightness.dark), sentraWhiteWordmarkAsset);
  });

  test('uses the black Sentra lockup on light surfaces', () {
    expect(sentraWordmarkAssetFor(Brightness.light), sentraBlackWordmarkAsset);
  });
}
