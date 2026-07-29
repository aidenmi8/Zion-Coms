part of '../pairing_page.dart';

class _PairingWelcomeView extends StatelessWidget {
  final _PairingBrandState brandState;
  final TextEditingController codeController;
  final String connectButtonLabel;
  final bool isBusy;
  final bool pairingCodeExpanded;
  final String? errorMessage;
  final VoidCallback onScan;
  final VoidCallback onTogglePairingCode;
  final VoidCallback onConnect;

  const _PairingWelcomeView({
    required this.brandState,
    required this.codeController,
    required this.connectButtonLabel,
    required this.isBusy,
    required this.pairingCodeExpanded,
    required this.errorMessage,
    required this.onScan,
    required this.onTogglePairingCode,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final revealDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Grid.gutter,
            Grid.sm,
            Grid.gutter,
            Grid.sm,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (Grid.sm * 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  key: const ValueKey('pairing-brand-status-region'),
                  container: true,
                  label: brandState.label,
                  liveRegion: brandState.liveRegion,
                  child: ExcludeSemantics(
                    child:
                        brandState.variant == ZionBrandMotionVariants.onboarding
                        ? const SentraLiquidOrbit(wordmarkHeight: 64)
                        : Container(
                            width: 136,
                            height: 136,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.colors.primary.withValues(
                                alpha: 0.12,
                              ),
                            ),
                            child: ZionBrandMotion(
                              variant: brandState.variant,
                              playing: brandState.playing,
                              loop: brandState.loop,
                              size: ZionBrandTokens.heroMotionSize,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: Grid.sm),
                Text(
                  'Welcome to Zion',
                  textAlign: TextAlign.center,
                  style: context.textTheme.headlineSmall?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: Grid.xxs),
                Text(
                  'Scan the QR code from your desktop app\nor paste a pairing code to connect.',
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Grid.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        FilledButton(
                          style: _onboardingButtonStyle(context),
                          onPressed: isBusy ? null : onScan,
                          child: Text(
                            isBusy && !pairingCodeExpanded
                                ? connectButtonLabel
                                : 'Scan a QR code',
                          ),
                        ),
                        const SizedBox(height: Grid.xxs),
                        TextButton(
                          style: _onboardingSecondaryButtonStyle(context),
                          onPressed: isBusy ? null : onTogglePairingCode,
                          child: Text(
                            pairingCodeExpanded
                                ? 'Hide pairing code'
                                : 'Use pairing code',
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: revealDuration,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return SizeTransition(
                              sizeFactor: animation,
                              axisAlignment: -1,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            );
                          },
                          child: pairingCodeExpanded
                              ? Column(
                                  key: const ValueKey('pairing-code-fields'),
                                  children: [
                                    const SizedBox(height: Grid.twelve),
                                    TextField(
                                      controller: codeController,
                                      style: context.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: context.colors.onSurface,
                                          ),
                                      cursorColor: context.colors.primary,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: context
                                            .colors
                                            .surfaceContainerHighest,
                                        hintText:
                                            'nostrpair://... or buzz://...',
                                        hintStyle: context.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: context
                                                  .colors
                                                  .onSurfaceVariant,
                                            ),
                                        prefixIcon: Icon(
                                          LucideIcons.link,
                                          color:
                                              context.colors.onSurfaceVariant,
                                        ),
                                        enabledBorder: _inputBorder(context),
                                        disabledBorder: _inputBorder(context),
                                        focusedBorder: _inputBorder(context)
                                            .copyWith(
                                              borderSide: BorderSide(
                                                color: context.colors.primary,
                                              ),
                                            ),
                                        isDense: true,
                                      ),
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      enabled: !isBusy,
                                      contextMenuBuilder:
                                          (context, editableTextState) {
                                            return AdaptiveTextSelectionToolbar.editableText(
                                              editableTextState:
                                                  editableTextState,
                                            );
                                          },
                                    ),
                                    const SizedBox(height: Grid.twelve),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        style: _onboardingButtonStyle(context),
                                        onPressed: isBusy ? null : onConnect,
                                        child: Text(connectButtonLabel),
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox(
                                  key: ValueKey('pairing-code-fields-hidden'),
                                ),
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: Grid.twelve),
                          Container(
                            padding: const EdgeInsets.all(Grid.twelve),
                            decoration: BoxDecoration(
                              color: context.colors.errorContainer,
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.triangleAlert,
                                  size: 16,
                                  color: context.colors.onErrorContainer,
                                ),
                                const SizedBox(width: Grid.xxs),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: context.textTheme.bodySmall
                                        ?.copyWith(
                                          color:
                                              context.colors.onErrorContainer,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

OutlineInputBorder _inputBorder(BuildContext context) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(Radii.md),
  borderSide: BorderSide(color: context.colors.outline),
);

ButtonStyle _onboardingButtonStyle(BuildContext context) =>
    FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(
        horizontal: Grid.lg,
        vertical: Grid.twelve,
      ),
      backgroundColor: context.colors.primary,
      foregroundColor: context.colors.onPrimary,
      disabledBackgroundColor: context.colors.primary.withValues(alpha: 0.38),
      disabledForegroundColor: context.colors.onPrimary.withValues(alpha: 0.7),
      shape: const StadiumBorder(),
    );

ButtonStyle _onboardingSecondaryButtonStyle(BuildContext context) =>
    TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(
        horizontal: Grid.md,
        vertical: Grid.xxs,
      ),
      backgroundColor: context.colors.surfaceContainerHighest,
      foregroundColor: context.colors.onSurface,
      disabledBackgroundColor: context.colors.surfaceContainerHighest
          .withValues(alpha: 0.5),
      disabledForegroundColor: context.colors.onSurface.withValues(alpha: 0.45),
      shape: const StadiumBorder(),
    );
