import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'bots/care_bot_hub_page.dart';
import 'common/care_widgets.dart';
import 'onboarding/care_onboarding_page.dart';
import 'safety/care_safety_sheet.dart';
import 'share/care_share_sheet.dart';

enum _KeyStatus { loading, missing, ready }

/// Root UI shell.
///
/// Routes between first-run BYOK onboarding and the perpetual Care chat, and hosts
/// the native SafetyGate approval listener so high-risk requests can never be
/// silently ignored, regardless of which page is on screen.
class CareAppShell extends ConsumerStatefulWidget {
  const CareAppShell({super.key});

  @override
  ConsumerState<CareAppShell> createState() => _CareAppShellState();
}

class _CareAppShellState extends ConsumerState<CareAppShell> {
  /// Sticky so onboarding can finish its "test connection" step even after
  /// the key has already been saved.
  bool _onboarding = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      careSettingsProvider.select((s) {
        if (s.hasValue) {
          return s.value!.hasApiKey ? _KeyStatus.ready : _KeyStatus.missing;
        }
        return s.hasError ? _KeyStatus.missing : _KeyStatus.loading;
      }),
    );

    if (status == _KeyStatus.missing) _onboarding = true;

    final Widget page;
    if (status == _KeyStatus.loading && !_onboarding) {
      page = const _CareSplash(key: ValueKey('splash'));
    } else if (_onboarding) {
      page = CareOnboardingPage(
        key: const ValueKey('onboarding'),
        onFinished: () => setState(() => _onboarding = false),
      );
    } else {
      page = const CareBotHubPage(key: ValueKey('hub'));
    }

    return CareSafetyGateListener(
      child: CareShareListener(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: page,
        ),
      ),
    );
  }
}

class _CareSplash extends StatelessWidget {
  const _CareSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CareAvatar(size: 72)),
    );
  }
}
