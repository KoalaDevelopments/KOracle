import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kodev_ui/kodev_ui.dart';

/// The app's theme, in the Design System's terms: square corners, IBM Plex Mono,
/// no shadows. kodev_ui has no buttons or fields yet, so Material's are themed.
ThemeData koracleTheme() {
  const colors = KODevColors.dark;
  const square = WidgetStatePropertyAll(RoundedRectangleBorder());
  const padding = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: KODevSpace.space6));
  const minimumSize = WidgetStatePropertyAll(Size(48, 48));
  final focusRing = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) => states.contains(WidgetState.focused)
        ? BorderSide(color: colors.focusRing, width: 2)
        : null,
  );
  OutlineInputBorder border(Color color) =>
      OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: color));

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KODevPalette.primary,
      brightness: Brightness.dark,
      surface: colors.bg,
    ),
    textTheme: GoogleFonts.ibmPlexMonoTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ).apply(bodyColor: colors.ink, displayColor: colors.ink),
    splashFactory: NoSplash.splashFactory,
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: square,
        padding: padding,
        minimumSize: minimumSize,
        side: focusRing,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? colors.inkMuted : colors.onAccent,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.bgRaised
              : states.contains(WidgetState.pressed)
              ? colors.accentPressed
              : states.contains(WidgetState.hovered)
              ? colors.accentHover
              : colors.accent,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: square,
        padding: padding,
        minimumSize: minimumSize,
        foregroundColor: WidgetStatePropertyAll(colors.ink),
        side: WidgetStatePropertyAll(BorderSide(color: colors.borderStrong)),
        overlayColor: WidgetStatePropertyAll(colors.bgRaised),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.bgRaised,
      hintStyle: TextStyle(color: colors.inkMuted),
      border: border(colors.border),
      enabledBorder: border(colors.border),
      focusedBorder: border(colors.focusRing),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(colors.onAccent),
      side: BorderSide(color: colors.borderStrong),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(side: BorderSide(color: colors.border)),
    ),
    extensions: const [colors],
  );
}
