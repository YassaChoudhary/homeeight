/// Paths to the SVG icons shipped from Figma.
///
/// One place for every asset path, for the same reason `NavIcons` exists: the
/// Figma export has a history of shipping glyphs under unhelpful or swapped
/// names (`Group 1171275372.svg`, and in an earlier round two icons under each
/// other's names). The files were renamed on import to say what they draw, and
/// these constants are what the screens reference — so a future re-export only
/// needs fixing here.
class AppIcons {
  AppIcons._();

  // --- Home hero -----------------------------------------------------------
  /// Notification bell, top-right of the Home hero.
  static const String bell = 'assets/icons/bell.svg';

  /// Small solid map pin beside the city name.
  static const String pinSmall = 'assets/icons/pin_small.svg';

  // --- Search / results controls -------------------------------------------
  /// Two sliders with knobs — the filter button.
  static const String filterSliders = 'assets/icons/filter_sliders.svg';

  /// Up/down arrow pair — the sort button.
  static const String sortArrows = 'assets/icons/sort_arrows.svg';

  /// Thin vertical rule that separates the filter and sort controls.
  static const String controlDivider = 'assets/icons/control_divider.svg';

  // --- Property detail -----------------------------------------------------
  /// Sphere with an equator band — the "360° Tour" tag.
  static const String tour360 = 'assets/icons/tour_360.svg';
  static const String contactEmail = 'assets/icons/contact_email.svg';
  static const String contactCall = 'assets/icons/contact_call.svg';
  static const String contactWhatsapp = 'assets/icons/contact_whatsapp.svg';

  /// Opposed arrows, used on the Compare affordance.
  static const String compareArrows = 'assets/icons/compare_arrows.svg';

  // --- Auth / account ------------------------------------------------------
  /// Grid of squares with a magnifier — "Find a Property".
  static const String purposeFind = 'assets/icons/purpose_find.svg';

  /// House containing a person — "List a property".
  static const String purposeList = 'assets/icons/purpose_list.svg';

  static const String authPhone = 'assets/icons/auth_phone.svg';
  static const String authEmail = 'assets/icons/auth_email.svg';

  /// Globe, for Language & market.
  static const String globe = 'assets/icons/globe.svg';

  /// Solid amber heart, for the Saved Items tile.
  static const String heartSolid = 'assets/icons/heart_solid.svg';

  /// Outlined heart with an amber badge — the "Nothing saved yet" graphic.
  static const String savedEmpty = 'assets/icons/saved_empty.svg';
}
