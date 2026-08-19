import 'package:flutter/material.dart';

/// Home8 design tokens — Section 7.2 of the Product Blueprint.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF12A0A2);
  static const Color primaryDark = Color(0xFF0C7B7D);
  static const Color primaryTint = Color(0xFFE4F0F0);

  static const Color accent = Color(0xFFE07A3C);
  static const Color accentTint = Color(0xFFFDECDF);

  /// Warm amber sampled from the Figma frames. Used for the
  /// Residential/Commercial segment toggle, listing badges and the Chats
  /// count — all of which read noticeably more golden than [accent].
  static const Color amber = Color(0xFFF0A32C);

  static const Color success = Color(0xFF2C7A54);
  static const Color warning = Color(0xFFB5731E);
  static const Color danger = Color(0xFFB24A38);

  static const Color ink = Color(0xFF1A2B34);
  static const Color inkMuted = Color(0xFF55666E);
  static const Color line = Color(0xFFD8E1E2);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color bg = Color(0xFFF5F8F8);

  // Bottom nav / dark chrome tone sampled from the mock screens.
  static const Color navDark = Color(0xFF1B2336);

  /// Teal for use ON [navDark].
  ///
  /// [primary] is tuned for white surfaces and reads muddy on the dark panels
  /// (nav bar, profile header, the "What you get once verified" card). This is
  /// the lifted value those surfaces actually use — it already existed as
  /// `HomeNavBar.activeColor`; promoting it to a token stops the next dark
  /// surface from sampling a fourth teal out of the Figma.
  static const Color primaryOnDark = Color(0xFF3FD6C8);
}
