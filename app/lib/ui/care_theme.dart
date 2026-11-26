import 'dart:async';

import 'package:care_app/state/care_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const kCareThemeModePrefsKey = 'care.ui.themeMode.v1';

/// Persisted light / dark / system appearance preference (manual Riverpod 3 Notifier).
final careThemeModeProvider = NotifierProvider<CareThemeModeController, ThemeMode>(
  CareThemeModeController.new,
);

class CareThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    unawaited(_load());
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final raw =
          await ref.read(carePrefsStoreProvider).getString(kCareThemeModePrefsKey);
      final parsed = _parse(raw);
      if (parsed != state) state = parsed;
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      await ref
          .read(carePrefsStoreProvider)
          .setString(kCareThemeModePrefsKey, mode.name);
    } catch (_) {}
  }

  static ThemeMode _parse(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// Care visual language: airy pale sky-blue mist + crisp white cards,
/// harmonizing with the white + cobalt-azure handwritten "Care" launcher icon.
abstract final class CareTheme {
  static const Color seed = Color(0xFF3B93FF);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Distinct midnight-indigo stealth theme used exclusively inside Privacy Bot.
  static ThemeData privacyDark() {
    final base = _build(Brightness.dark);
    final scheme = base.colorScheme.copyWith(
      primary: const Color(0xFF9EA8FF),
      onPrimary: const Color(0xFF141840),
      primaryContainer: const Color(0xFF232859),
      onPrimaryContainer: const Color(0xFFE0E4FF),
      surface: const Color(0xFF0E1324),
      surfaceContainerLow: const Color(0xFF151C33),
      surfaceContainer: const Color(0xFF1B2340),
      surfaceContainerHigh: const Color(0xFF212B4C),
      surfaceContainerHighest: const Color(0xFF28345B),
      outlineVariant: const Color(0xFF33406E),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );
  }

  static SystemUiOverlayStyle overlayStyleFor({required bool isLight}) =>
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
        statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isLight ? Brightness.dark : Brightness.light,
      );

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final scheme = isLight
        ? base.copyWith(
            primary: const Color(0xFF2E86F7),
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFE3F0FF),
            onPrimaryContainer: const Color(0xFF104080),
            secondary: const Color(0xFF5683B8),
            secondaryContainer: const Color(0xFFE9F2FD),
            onSecondaryContainer: const Color(0xFF1E436E),
            surface: const Color(0xFFF3F8FF),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Colors.white,
            surfaceContainer: const Color(0xFFEEF5FF),
            surfaceContainerHigh: const Color(0xFFE8F1FE),
            surfaceContainerHighest: const Color(0xFFE0ECFC),
            outlineVariant: const Color(0xFFD7E4F5),
          )
        : base.copyWith(
            primary: const Color(0xFF78B8FF),
            onPrimary: const Color(0xFF0A2850),
            primaryContainer: const Color(0xFF19375C),
            onPrimaryContainer: const Color(0xFFD6E9FF),
            surface: const Color(0xFF0F1724),
            surfaceContainerLow: const Color(0xFF162133),
            surfaceContainer: const Color(0xFF1B283D),
            surfaceContainerHigh: const Color(0xFF213049),
            surfaceContainerHighest: const Color(0xFF273956),
            outlineVariant: const Color(0xFF2B3E5B),
          );

    final fieldRadius = BorderRadius.circular(16);

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyleFor(isLight: isLight),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isLight ? 0.65 : 0.45),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : scheme.surfaceContainerHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: const StadiumBorder()),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 18),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        space: 1,
        thickness: 1,
      ),
    );
  }
}

/// Subtle Today-inspired pale sky-blue → soft morning mist backdrop, or
/// deep midnight-indigo stealth backdrop for Privacy Bot.
class CareAtmosphereBackground extends StatelessWidget {
  const CareAtmosphereBackground({
    super.key,
    required this.child,
    this.stealth = false,
  });

  final Widget child;
  final bool stealth;

  @override
  Widget build(BuildContext context) {
    final isLight = !stealth && Theme.of(context).brightness == Brightness.light;
    final colors = stealth
        ? const [
            Color(0xFF161D38),
            Color(0xFF0E1324),
            Color(0xFF0A0E1B),
          ]
        : isLight
            ? const [
                Color(0xFFE6F2FF),
                Color(0xFFF5F9FF),
                Color(0xFFFAF8F4),
              ]
            : const [
                Color(0xFF132033),
                Color(0xFF0F1724),
                Color(0xFF0E1420),
              ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: CareTheme.overlayStyleFor(isLight: isLight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: child,
      ),
    );
  }
}
