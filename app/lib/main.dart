import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'ui/care_app_shell.dart';
import 'ui/care_theme.dart';
import 'ui/safety/care_emergency_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CareApp()));
}

class CareApp extends ConsumerWidget {
  const CareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(careThemeModeProvider);
    return MaterialApp(
      title: 'Care',
      debugShowCheckedModeBanner: false,
      theme: CareTheme.light(),
      darkTheme: CareTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) =>
          CareEmergencyOverlay(child: child ?? const SizedBox.shrink()),
      home: const CareAppShell(),
    );
  }
}
