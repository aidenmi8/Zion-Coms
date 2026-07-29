import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nostr/nostr.dart' as nostr;
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/push_companion_provider.dart';
import '../../shared/auth/auth.dart';
import '../../shared/brand/zion_release.dart';
import '../../shared/branding/sentra_branding.dart';
import '../../shared/clipboard_utils.dart';
import '../../shared/relay/relay.dart';
import '../../shared/theme/theme.dart';
import '../../shared/watch/push_lease_coordinator.dart';
import '../../shared/widgets/app_list.dart';
import '../../shared/widgets/app_list_card.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import 'accent_picker_page.dart';
import 'theme_picker_page.dart';

part 'settings_page/appearance_section.dart';
part 'settings_page/connection_section.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key, required this.profileHeader});

  final Widget profileHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfoFuture = useMemoized(() => PackageInfo.fromPlatform());
    final packageInfo = useFuture(packageInfoFuture);

    return FrostedScaffold(
      appBar: const FrostedAppBar(title: Text('Settings')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                top: frostedAppBarHeight(context),
                bottom: Grid.xs,
              ),
              children: [
                profileHeader,
                const _AppearanceSection(),
                const _ConnectionSection(),
                const _RemoveCommunitySection(),
                const AppListCard(
                  label: 'Notifications & Watch',
                  children: [_PushCompanionRow()],
                ),
              ],
            ),
          ),
          if (packageInfo.hasData)
            _VersionFooter(version: packageInfo.data!.version),
        ],
      ),
    );
  }
}

class _PushCompanionRow extends ConsumerWidget {
  const _PushCompanionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pushCompanionControllerProvider);
    final status = switch (state.status) {
      PushCompanionStatus.off => 'Off',
      PushCompanionStatus.enabling => 'Enabling',
      PushCompanionStatus.active => 'Active',
      PushCompanionStatus.needsAttention => 'Needs Attention',
      PushCompanionStatus.unsupported => 'Unsupported',
    };
    final subtitle = switch (state.status) {
      PushCompanionStatus.off =>
        'Receive agent messages and approval requests on Apple Watch.',
      PushCompanionStatus.enabling =>
        'Requesting notification access and securing this iPhone.',
      PushCompanionStatus.active =>
        'Alerts are active. Apple Watch uses this iPhone’s focused queue.',
      PushCompanionStatus.needsAttention =>
        state.message ?? 'Allow notifications in iOS Settings → Zion.',
      PushCompanionStatus.unsupported =>
        'Requires a supported iPhone with App Attest.',
    };
    final canEnable =
        state.status == PushCompanionStatus.off ||
        state.status == PushCompanionStatus.needsAttention;

    return AppListRow(
      icon: LucideIcons.watch,
      title: 'Apple Watch companion',
      subtitle: subtitle,
      subtitleMaxLines: 3,
      trailing: Text(
        status,
        style: context.textTheme.bodySmall?.copyWith(
          color: state.status == PushCompanionStatus.needsAttention
              ? context.colors.error
              : context.colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: canEnable
          ? () async {
              await ref.read(pushCompanionControllerProvider.notifier).enable();
            }
          : null,
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Grid.xs, top: Grid.xxs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Sentra',
              image: true,
              child: Image.asset(
                sentraWordmarkAssetFor(context.colors.brightness),
                height: 36,
              ),
            ),
            const SizedBox(height: Grid.xxs),
            Text(
              formatZionReleaseLabel(version, currentZionReleaseChannel),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trailing affordance shared by the rows that push a picker page.
class _RowChevron extends StatelessWidget {
  const _RowChevron();

  @override
  Widget build(BuildContext context) {
    return Icon(
      LucideIcons.chevronRight,
      size: 18,
      color: context.colors.onSurfaceVariant,
    );
  }
}
