import '../models/lister_profile.dart';
import '../models/listing_draft.dart';
import '../models/my_listing.dart';
import '../models/property.dart';
import '../models/search_query.dart';

/// The single seam between the UI and whatever serves the data.
///
/// No screen, controller or widget imports mock data directly — they all go
/// through this interface. When the backend is ready you write one
/// `ApiListingRepository implements ListingRepository`, swap the instance
/// passed to `AppScope` in `main.dart`, and nothing above this line changes.
///
/// Method names and parameters mirror the endpoints in blueprint §9.3 so the
/// mapping stays one-to-one:
///   search()              -> GET  /search
///   propertyById()        -> GET  /listings/{id}
///   similarTo()           -> GET  /listings/{id}/similar
///   comparables()         -> GET  /listings/{id}/comparables
///   popularCommunities()  -> GET  /communities/popular
///   suggest()             -> GET  /search/suggest
///   reels()               -> GET  /reels
///   toggleSaved()         -> POST/DELETE /saved-listings
///
/// Seller side (screens 29–39):
///   listerStats()         -> GET    /me/stats
///   myListings()          -> GET    /me/listings
///   listingPerformance()  -> GET    /me/listings/{id}/performance
///   priceGuidance()       -> POST   /pricing/guidance
///   saveListingDraft()    -> PUT    /listings/{id}/draft
///   submitListing()       -> POST   /listings
///   updateListingStatus() -> PATCH  /listings/{id}
///   deleteListing()       -> DELETE /listings/{id}
///   boostListing()        -> POST   /listings/{id}/boost
///   submitVerification()  -> POST   /me/verification
abstract class ListingRepository {
  Future<ListingPage> search(SearchQuery query);

  Future<Property> propertyById(String id);

  Future<List<Property>> similarTo(String id, {int limit = 6});

  /// Evidence behind the Fair Price verdict — the homes the band was computed
  /// from. Powers the Fair Price sheet and the Compare screen.
  Future<List<ComparableListing>> comparables(String id, {int limit = 6});

  /// Home "The most relevant" / Search "Best deals for you" carousels.
  Future<List<Property>> highlights({int limit = 8});

  Future<List<Community>> popularCommunities({int limit = 4});

  Future<List<SearchSuggestion>> suggest(String term);

  Future<List<String>> recentSearches();

  Future<List<Reel>> reels();

  /// Returns the new saved state. Optimistic UI calls this and rolls back on
  /// throw, so the signature stays the same once it hits a real endpoint.
  Future<bool> toggleSaved(String listingId, {required bool saved});

  // -------------------------------------------------------------------------
  // Seller side
  //
  // Everything below belongs to the "List a property" user. It sits on the same
  // interface rather than a second `SellerRepository` because it hits the same
  // service with the same auth, and splitting it would mean two instances to
  // inject and two mocks to keep in step, for no gain.
  // -------------------------------------------------------------------------

  /// The four figures in the dark profile header — saved, listings, viewings,
  /// rating — plus the trust score behind the "TRUST 92" pill.
  Future<ListerStats> listerStats();

  /// Every listing the signed-in user owns, in any status.
  Future<List<MyListing>> myListings();

  Future<ListingPerformance> listingPerformance(
    String listingId, {
    PerformanceRange range = PerformanceRange.days30,
  });

  /// The fair-price band for what's been entered so far, shown live under the
  /// price field on the details step.
  ///
  /// Takes the whole draft rather than loose parameters because the band
  /// depends on type, area, beds, BUA and furnishing together — and every one
  /// of those is a field the user can still change.
  Future<FairPrice> priceGuidance(ListingDraft draft);

  /// Persists a partial draft. Returns it with [ListingDraft.id] filled in on
  /// first save, so the next call updates rather than duplicating.
  Future<ListingDraft> saveListingDraft(ListingDraft draft);

  /// Sends a completed draft for review. Returns the resulting listing, which
  /// comes back as [ListingStatus.inReview] — never live immediately, because
  /// permit and photo checks happen server-side.
  Future<MyListing> submitListing(ListingDraft draft);

  /// Used by the row menu: mark rented, mark sold, pause, republish.
  Future<MyListing> updateListingStatus(String id, ListingStatus status);

  Future<void> deleteListing(String id);

  /// Buys featured placement. Returns the listing with its boost applied; the
  /// payment sheet is a separate concern and doesn't exist yet.
  Future<MyListing> boostListing(String id);

  /// Sends company/licence documents for review (screen 29). Returns the
  /// profile with its status advanced to [VerificationStatus.pending].
  Future<ListerProfile> submitVerification(ListerProfile profile);
}
