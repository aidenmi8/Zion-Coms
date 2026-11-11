part of '../pairing_page.dart';

// Zion artwork and palette over the upstream decorative motion layer.
class _WebsiteWelcomeBackground extends HookWidget {
  final Widget child;
  final ValueListenable<double> scannerProgress;

  const _WebsiteWelcomeBackground({
    required this.child,
    required this.scannerProgress,
  });

  @override
  Widget build(BuildContext context) {
    final pointer = useRef<Offset?>(null);
    final theme = AppTheme.dark();
    return MouseRegion(
      onHover: (event) => pointer.value = event.localPosition,
      onExit: (_) => pointer.value = null,
      child: Listener(
        onPointerDown: (event) => pointer.value = event.localPosition,
        onPointerMove: (event) => pointer.value = event.localPosition,
        onPointerUp: (_) => pointer.value = null,
        onPointerCancel: (_) => pointer.value = null,
        child: DecoratedBox(
          key: const Key('pairing-website-welcome-background'),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A0A0A), Color(0xFF1C1C1E), Color(0xFF0A0A0A)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.95, -0.9),
                        radius: 1.15,
                        colors: [Color(0x194E7CFF), Color(0x004E7CFF)],
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-1, 1),
                        radius: 1.15,
                        colors: [Color(0x284E7CFF), Color(0x004E7CFF)],
                      ),
                    ),
                  ),
                ),
              ),
              if (MediaQuery.textScalerOf(context).scale(16) <= 24)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: ValueListenableBuilder<double>(
                        valueListenable: scannerProgress,
                        builder: (context, progress, child) => Opacity(
                          key: const Key('scanner-bees-opacity'),
                          opacity: 1 - progress,
                          child: Transform.scale(
                            key: const Key('scanner-bees-scale'),
                            scale: MediaQuery.disableAnimationsOf(context)
                                ? 1
                                : 1 - 0.04 * progress,
                            child: TickerMode(
                              enabled: progress < 1,
                              child: child!,
                            ),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) => RepaintBoundary(
                            child: _WebsiteBeeSwarm(
                              size: constraints.biggest,
                              pointer: pointer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Theme(
                data: theme.copyWith(
                  textButtonTheme: TextButtonThemeData(
                    style: theme.textButtonTheme.style?.copyWith(
                      backgroundColor: const WidgetStatePropertyAll(
                        Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
