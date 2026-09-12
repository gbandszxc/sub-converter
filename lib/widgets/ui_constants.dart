import 'package:flutter/material.dart';

/// Shared spacing and sizing constants for the window chrome.
///
/// Keeping them here avoids scattering magic numbers through the widgets.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Width of the right-hand options panel.
  static const double optionsPanelWidth = 320;

  /// Height of the header, status bar and list rows.
  static const double headerHeight = 52;
  static const double statusBarHeight = 40;
  static const double rowHeight = 56;

  static const double chipRadius = 4;
  static const double panelRadius = 8;
}

/// Text styles that stay compact and information dense on desktop.
abstract final class AppTextStyles {
  static const TextStyle appTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(fontSize: 13);

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle caption = TextStyle(fontSize: 12);
}

/// Builds the muted foreground colour used for secondary lines.
Color mutedColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
