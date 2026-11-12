import 'package:flutter/material.dart';

import 'buzz_loading_indicator.dart';

/// Zion loading art in the existing onboarding loading slot.
/// The internal name is retained to avoid changing upstream flow consumers.
class BeeLoadingMark extends StatelessWidget {
  const BeeLoadingMark({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 80,
    height: 80 * 309 / 466,
    child: Center(child: BuzzLoadingIndicator(size: 48)),
  );
}
