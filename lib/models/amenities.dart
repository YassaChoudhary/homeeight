import 'search_query.dart';

/// The "What this place offers" catalogue — what sellers pick on the details
/// step and buyers see as chips on the listing. The first five are also the
/// Filters sheet's amenity options, so anything filterable can be posted.
class Amenities {
  Amenities._();

  static const List<String> residential = [
    'Shared Pool',
    'Private Gym',
    'Covered Parking',
    'Sea View',
    "Maid's Room",
    'Wifi',
    '65" HD TV',
    'Central A/C & Heating',
    'CCTV Security',
    'Balcony',
    'Private Pool',
    'Private Garden',
    'Built-in Wardrobes',
    'Study Room',
    'Kids Play Area',
    'Pets Allowed',
    'Concierge',
    'Maintenance Staff',
    'Laundry Room',
    'Elevator',
  ];

  static const List<String> commercial = [
    'Covered Parking',
    'Meeting Rooms',
    '24/7 Access',
    'Pantry',
    'Central A/C & Heating',
    'CCTV Security',
    'Wifi',
    'Reception Area',
    'Loading Bay',
    'Elevator',
    'Maintenance Staff',
    'Sea View',
  ];

  static List<String> forSegment(PropertySegment segment) =>
      segment == PropertySegment.commercial ? commercial : residential;
}
