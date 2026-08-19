import 'package:flutter/material.dart';

/// Google and Apple logos for the social sign-in buttons.
///
/// One widget for both so every auth surface renders them identically — the
/// login screen, the email-login screen and the save-gate sheet were each
/// drawing their own version before, and they didn't match.
///
/// The marks are shipped as PNG assets rather than drawn in code. Both
/// companies publish sign-in button guidelines that require the official
/// artwork, unmodified — so these must not be recoloured, outlined, or
/// redrawn. If you ever need a white-on-dark variant, add a second asset
/// rather than applying a colour filter to these.
///
/// Apple additionally requires that "Sign in with Apple" is offered on iOS
/// whenever other third-party sign-in options are present, or the app is
/// rejected at review. That's a backend/plumbing task, not a UI one — worth
/// tracking before the first TestFlight build.
enum BrandLogo { google, apple }

class BrandMark extends StatelessWidget {
  final BrandLogo logo;
  final double size;

  const BrandMark(this.logo, {super.key, this.size = 22});

  /// Apple's glyph reads visually smaller than Google's at the same box size,
  /// because the mark doesn't fill its own square. Nudging it up keeps the two
  /// buttons looking balanced side by side.
  double get _effectiveSize =>
      logo == BrandLogo.apple ? size * 1.05 : size;

  String get _asset => switch (logo) {
        BrandLogo.google => 'assets/images/brands/google.png',
        BrandLogo.apple => 'assets/images/brands/apple.png',
      };

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Image.asset(
          _asset,
          width: _effectiveSize,
          height: _effectiveSize,
          fit: BoxFit.contain,
          // Source art is 512px square; decode down to what's actually drawn.
          cacheWidth: (_effectiveSize * dpr).round(),
          filterQuality: FilterQuality.medium,
          // No colorFilter — brand terms require the marks unmodified.
        ),
      ),
    );
  }
}
