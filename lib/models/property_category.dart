import 'package:flutter/foundation.dart';

import 'search_query.dart';

/// One category tile / property type.
///
/// ## Why this exists
///
/// The Home grid and the Filters sheet both need this list, and until now each
/// had its own hardcoded copy — the grid said "Studio", the filter said
/// "Studio (Studio & 1 BHK)", and neither knew about the other. So a type you
/// tapped on Home could not be selected in Filters, and adding a category meant
/// editing two files and hoping. This is the single source of truth for both.
///
/// [wire] is what goes to the backend and what `SearchQuery.propertyType`
/// stores. [title] is what the user reads. Keeping them separate means the
/// display copy can change without breaking a saved search or a deep link.
@immutable
class PropertyCategory {
  /// Display name, single line. Used by the Filters dropdown.
  final String title;

  /// Supporting line on the Home grid tile.
  final String subtitle;

  /// Display name with an explicit break, for the narrow grid tiles. Falls back
  /// to [title] when it fits on one line.
  final String? gridTitle;

  final String asset;

  /// Value stored in `SearchQuery.propertyType` and sent as `type=`.
  final String wire;

  const PropertyCategory({
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.wire,
    this.gridTitle,
  });

  /// What the Home grid renders — two lines where the design breaks them.
  String get gridLabel => gridTitle ?? title;

  static const List<PropertyCategory> residential = [
    PropertyCategory(
      title: 'Studio',
      subtitle: 'Studio & 1 BHK',
      asset: 'assets/images/categories/residential/studio.png',
      wire: 'studio',
    ),
    PropertyCategory(
      title: 'Apartment',
      subtitle: '2 & 3 BHK',
      asset: 'assets/images/categories/residential/apartment.png',
      wire: 'apartment',
    ),
    PropertyCategory(
      title: 'Penthouses',
      subtitle: '4 BHK & above',
      asset: 'assets/images/categories/residential/penthouses.png',
      wire: 'penthouse',
    ),
    PropertyCategory(
      title: 'Villas & Townhouses',
      gridTitle: 'Villas &\nTownhouses',
      subtitle: 'Independent homes',
      asset: 'assets/images/categories/residential/villas.png',
      wire: 'villa',
    ),
    PropertyCategory(
      title: 'Hotel Apartments',
      gridTitle: 'Hotel\nApartments',
      subtitle: 'Serviced & furnished',
      asset: 'assets/images/categories/residential/hotel_apartments.png',
      wire: 'hotel',
    ),
    PropertyCategory(
      title: 'Short Stays',
      subtitle: 'Daily & monthly',
      asset: 'assets/images/categories/residential/short_stays.png',
      wire: 'short_stay',
    ),
    PropertyCategory(
      title: 'Shared Rooms',
      subtitle: 'Family sharing',
      asset: 'assets/images/categories/residential/shared_rooms.png',
      wire: 'shared_room',
    ),
    PropertyCategory(
      title: 'Bed Space',
      subtitle: 'Beds & partitions',
      asset: 'assets/images/categories/residential/bed_space.png',
      wire: 'bed_space',
    ),
    // The off-plan wire value is what `SearchQuery.isOffPlan` matches on to
    // swap the Filters sheet to its off-plan variant. Don't rename it without
    // updating that getter.
    PropertyCategory(
      title: 'Off-Plan Homes',
      subtitle: 'Launching soon',
      asset: 'assets/images/categories/residential/off_plan.png',
      wire: 'Off-Plan Homes',
    ),
  ];

  static const List<PropertyCategory> commercial = [
    PropertyCategory(
      title: 'Offices',
      subtitle: 'Fitted & shell',
      asset: 'assets/images/categories/commercial/offices.png',
      wire: 'office',
    ),
    PropertyCategory(
      title: 'Co-Working',
      subtitle: 'Desks & cabins',
      asset: 'assets/images/categories/commercial/coworking.png',
      wire: 'coworking',
    ),
    PropertyCategory(
      title: 'Retail Shops',
      subtitle: 'Malls & high street',
      asset: 'assets/images/categories/commercial/retail.png',
      wire: 'retail',
    ),
    PropertyCategory(
      title: 'Restaurants & Cafés',
      gridTitle: 'Restaurants\n& Cafés',
      subtitle: 'Fitted F&B units',
      asset: 'assets/images/categories/commercial/restaurants.png',
      wire: 'fnb',
    ),
    PropertyCategory(
      title: 'Clinics',
      subtitle: 'Medical & wellness',
      asset: 'assets/images/categories/commercial/clinics.png',
      wire: 'clinic',
    ),
    PropertyCategory(
      title: 'Warehouses',
      subtitle: 'Storage & logistics',
      asset: 'assets/images/categories/commercial/warehouses.png',
      wire: 'warehouse',
    ),
    PropertyCategory(
      title: 'Event Halls',
      subtitle: 'Book by the hour',
      asset: 'assets/images/categories/commercial/event_halls.png',
      wire: 'event_hall',
    ),
    PropertyCategory(
      title: 'Sports Courts',
      subtitle: 'Book by the slot',
      asset: 'assets/images/categories/commercial/sports_courts.png',
      wire: 'sports_court',
    ),
    PropertyCategory(
      title: 'Off-Plan Units',
      subtitle: 'Launching soon',
      asset: 'assets/images/categories/commercial/off_plan_units.png',
      wire: 'Off-Plan Homes',
    ),
  ];

  /// The categories valid for a given property nature.
  static List<PropertyCategory> forSegment(PropertySegment segment) =>
      segment == PropertySegment.residential ? residential : commercial;

  /// Looks up a category by its wire value within one segment.
  ///
  /// Returns null when the value doesn't belong to that segment — which is
  /// exactly what the Filters sheet needs in order to notice that switching
  /// nature has invalidated the selected type.
  static PropertyCategory? lookup(PropertySegment segment, String? wire) {
    if (wire == null) return null;
    for (final c in forSegment(segment)) {
      if (c.wire == wire) return c;
    }
    return null;
  }

  /// Display name for a stored wire value, searching both segments.
  ///
  /// Used by the results header and chips, which have a type but not
  /// necessarily the segment it came from.
  static String? titleForWire(String? wire) {
    if (wire == null) return null;
    for (final c in [...residential, ...commercial]) {
      if (c.wire == wire) return c.title;
    }
    return wire;
  }
}
