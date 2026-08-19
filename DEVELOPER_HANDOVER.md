# Home8 — Flutter Frontend Handover

**Project:** `homeeightflutterapp` · package `homeeight`
**Status:** frontend only. No backend exists yet. All data comes from an
in-memory mock behind a repository interface.
**Stack:** Flutter (Dart SDK `^3.11.1`), 2 dependencies — `cupertino_icons`,
`flutter_svg`. No state-management package, no HTTP client, no router.
**Size:** ~16,100 lines of Dart across 56 files.

Read this alongside `CHANGES.md`. Round 1 built the architecture; round 2
(recorded in `CHANGES.md`) rebuilt the Home screen and added the Fair Price,
Share, Compare, Mortgage and Gallery screens.

---

## 1. What this app is

A property marketplace client built from a Figma handoff (16 screens) and a
43-page product blueprint targeting UAE / KSA / Pakistan. The screens that exist
today cover: splash, onboarding carousel, market picker, language picker,
location permission, a Reels-style vertical media feed, Home/Discover
(residential + commercial category grids), Search with autocomplete, Results
list, Filters sheet (standard + off-plan variants), Sort sheet, No-results, and
Property detail.

Not built yet: chat, auth/login, post-a-listing, seller dashboard, saved
listings screen, admin console, map view. Chats and Login route to a labelled
`ComingSoonScreen`.

**The goal of the current phase** was to get the frontend to a state where the
backend can be connected without reworking UI code. That shaped most of the
architecture below.

---

## 2. Project layout

```
lib/
├── main.dart                 entry point; picks the repository implementation
├── core/
│   └── async_value.dart      AsyncValue<T> + RepositoryException
├── models/
│   ├── property.dart         Property, Agent, FairPrice, ComparableListing,
│   │                         Community, SearchSuggestion, Reel, formatters
│   ├── property_category.dart  PropertyCategory — the ONE category catalogue
│   └── search_query.dart     SearchQuery, SortOption, ListingPage
├── data/
│   ├── listing_repository.dart       ABSTRACT — the backend seam
│   └── mock_listing_repository.dart  in-memory implementation + seed data
├── state/
│   ├── app_scope.dart        Market, AppLanguage, AppState,
│   │                         SavedListingsStore, AppScope, AppStateBuilder
│   ├── auth_controller.dart  AuthUser, AuthController, UserIntent, DialCode
│   ├── connectivity_controller.dart  ConnectivityController, ConnectivityScope
│   └── net_probe*.dart       reachability probe (conditional io/web)
│   └── listings_controller.dart  ListingsController, AsyncController<T>
├── theme/                    UNCHANGED from the original handoff
│   ├── app_colors.dart
│   ├── app_spacing.dart      AppSpacing + AppRadius
│   ├── app_text_styles.dart
│   └── app_theme.dart
├── widgets/
│   ├── pill_button.dart      Pressable, PrimaryButton, GhostButton,
│   │                         TertiaryButton, OverlayPillButton, SheetDragHandle
│   ├── home_nav_bar.dart     NavTab enum, NavIcons, HomeNavBar
│   ├── property_image.dart   PropertyImage (network + gradient fallback)
│   ├── listing_card.dart     DealCard, ResultListingCard, SaveHeartButton,
│   │                         VerifiedPill, ListingBadge
│   └── state_views.dart      SkeletonBox, DealCardSkeleton, ResultCardSkeleton,
│                             ErrorStateView, EmptyStateView
└── screens/                  32 screens (see §5)
```

`assets/` holds 9 flags, 18 category illustrations (9 residential, 9
commercial), 10 SVG icons and the Circular Std font family (8 weights, all
declared in `pubspec.yaml`). **No listing photography shipped** — see §7.

---

## 3. Architecture — the four layers

This is the part that matters most for whoever wires up the backend.

### 3.1 Repository — `lib/data/listing_repository.dart`

One abstract class is the *only* thing the UI knows about where data comes from.
No screen, controller or widget imports mock data directly.

```dart
abstract class ListingRepository {
  Future<ListingPage> search(SearchQuery query);
  Future<Property> propertyById(String id);
  Future<List<Property>> similarTo(String id, {int limit = 6});
  Future<List<ComparableListing>> comparables(String id, {int limit = 6});
  Future<List<Property>> highlights({int limit = 8});
  Future<List<Community>> popularCommunities({int limit = 4});
  Future<List<SearchSuggestion>> suggest(String term);
  Future<List<String>> recentSearches();
  Future<List<Reel>> reels();
  Future<bool> toggleSaved(String listingId, {required bool saved});
}
```

Method names deliberately mirror the endpoints in blueprint §9.3:

| Method | Endpoint |
|---|---|
| `search()` | `GET /search` |
| `propertyById()` | `GET /listings/{id}` |
| `similarTo()` | `GET /listings/{id}/similar` |
| `comparables()` | `GET /listings/{id}/comparables` |
| `popularCommunities()` | `GET /communities/popular` |
| `suggest()` | `GET /search/suggest` |
| `reels()` | `GET /reels` |
| `toggleSaved()` | `POST` / `DELETE /saved-listings` |

`MockListingRepository` implements this today with **real** filtering, sorting,
pagination and a simulated 350 ms latency. That matters: the screens exercise
the same code paths they will against a live API, including the empty and error
branches, so those aren't discovered late.

**To connect the backend:** write `ApiListingRepository implements
ListingRepository`, then change one line in `main.dart`:

```dart
final ListingRepository repository = MockListingRepository();
// becomes
final ListingRepository repository = ApiListingRepository(baseUrl: Env.apiBaseUrl);
```

Nothing above that line changes. `MockListingRepository` can then be kept for
tests (`latency: Duration.zero`, `failEverything: true`).

### 3.2 Models — JSON already mapped

`Property.fromJson` and `ListingPage.fromJson` match the response shapes in
blueprint Appendix C.1, and `SearchQuery.toQueryParameters()` already emits the
`/search` query string (`purpose`, `bua_min`, `bua_max`, `beds`, `sort`,
`page`…). So the API repository is mostly `http.get` plus these constructors.

If the real API differs, change the `fromJson` bodies — not the widgets.

`Property` carries everything the detail screen needs: specs, occupancy,
furnishing, age, amenities, description, address, permit number, agent, and a
`FairPrice` with a `position` (0..1) that drives the gauge marker.

### 3.3 Controllers — `lib/state/listings_controller.dart`

`ListingsController` owns one results surface: the query, the current page,
`AsyncValue` state, `total`, `hasMore`, `loadingMore`, and a debounced
`setTerm`. It stamps each request with an id and drops stale responses, so a
slow first request can't overwrite a fast second one.

`AsyncController<T>` is the one-shot equivalent, used for highlights,
communities, suggestions, reels, and the detail record.

Screens render off `state.when(loading:, data:, error:)` — every async surface
has all three branches, so a flaky backend never produces a blank screen.

### 3.4 Scope — `lib/state/app_scope.dart`

A plain `InheritedWidget` carrying three things: the repository, `AppState`, and
`SavedListingsStore`. No package dependency; swapping to provider or riverpod
later means editing this file and the `of()` call sites, not the screens.

- **`AppState`** (`ChangeNotifier`) — market, language, currency override,
  location consent, onboarding-seen. Deliberately small, because every listener
  rebuilds when it changes. Selecting Arabic or Urdu flips `Directionality` for
  the whole app from `main.dart`, so RTL is structural rather than a retrofit.
- **`SavedListingsStore`** (`ValueNotifier<Set<String>>`) — separate from
  `AppState` so tapping a heart repaints hearts only. Optimistic: flips locally,
  calls the repository, rolls back on throw.

Access patterns:

```dart
AppScope.watch(context)          // read + subscribe (use in build)
AppScope.of(context)             // read without subscribing (callbacks/initState)
AppScope.repositoryOf(context)
AppScope.savedOf(context)
AppStateBuilder(builder: ...)    // rebuild only this subtree on AppState change
```

**Not yet persisted.** Adding `shared_preferences` and hydrating/writing in
`AppState` is roughly 20 lines and touches one file.

---

## 4. What changed, and what was already there

### 4.1 Untouched from the original handoff

- **`lib/theme/`** — three of four files byte-for-byte. `app_colors.dart` gained
  exactly one token in round 2, `AppColors.amber` (`#F0A32C`), for the Figma
  Residential/Commercial toggle. Everything else — the 4-pt spacing scale,
  `AppRadius`, the seven text styles, `AppTheme.light` — is untouched.
- **`assets/`** — every flag and font file. Two icons were *added* in round 2
  (`purpose_rent.svg`, `purpose_sale.svg`) and one illustration was *replaced*
  (`residential/studio.png`, which was a byte-identical copy of `villas.png`).
- **`pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`,
  `android/`, `ios/`, `web/`, `.metadata`, `.gitignore`** — all unchanged.
  **No new dependencies were added.**

Note: `AppColors.primary` is `#12A0A2`, not the blueprint's `#0D5C63`. The code
follows the Figma mockups here, which is the right call — flagging it only so
nobody "fixes" it against the PDF.

### 4.2 Deleted

- `lib/data/mock_data.dart` — superseded by `mock_listing_repository.dart`.

### 4.3 New files

| File | Why |
|---|---|
| `core/async_value.dart` | loading/data/error union + `RepositoryException` |
| `models/search_query.dart` | filters and sort as one immutable value object |
| `data/listing_repository.dart` | the backend seam |
| `data/mock_listing_repository.dart` | real filtering/sorting/pagination over seed data |
| `state/app_scope.dart` | session state + dependency injection |
| `state/listings_controller.dart` | async list state with pagination and debounce |
| `widgets/state_views.dart` | skeletons, error view, empty view |

### 4.4 Rewritten files

`main.dart`, `models/property.dart`, all four widgets, all fifteen screens,
`test/widget_test.dart`.

---

## 5. Bug fixes, with the cause

These were reported from device screenshots. Cause is recorded so the same class
of bug is recognisable next time.

**Buttons collapsed to label width.** `PrimaryButton` returned a bare
`SizedBox(height: 56, child: ElevatedButton(...))` with no width. Inside a
`CrossAxisAlignment.start` column that gives the button its intrinsic width — so
"Continue" on the market picker rendered as a small pill bottom-left instead of
full-bleed. Now full width by default (`expand: false` opts out, used only for
onboarding "Next"), with the teal glow from the mocks plus disabled and loading
states.

**Horizontal card list overflowed by 47 px.** `DealCard` put an
`AspectRatio(1.28)` image at 260 wide (= 203 pt) plus ~76 pt of text inside a
`SizedBox(height: 232)`. Fixed geometry is now published as constants —
`DealCard.height` (252), `DealCard.imageHeight` (150), `defaultWidth` (240) —
and every carousel sizes itself from `DealCard.height`, so the container and
its content can't drift apart again. The card also gained the white surface,
radius and shadow the Figma card has and the old one was missing.

**Nav bar icons showed the wrong glyphs.** The Figma export shipped two SVGs
under each other's names: `assets/icons/reels.svg` contains the *bookmark
ribbon*, and `assets/icons/bookmark.svg` contains the *two stacked cards*. So
the Reels tab drew a bookmark and the reel's save button drew the tab icon.
Rather than rename the assets, `NavIcons` in `home_nav_bar.dart` maps each slot
to the file holding the correct artwork:

```dart
static const String reelsTab  = 'assets/icons/bookmark.svg'; // stacked cards
static const String reelSave  = 'assets/icons/reels.svg';    // bookmark ribbon
```

If you do rename the files, `NavIcons` is the only place to edit.

**Nav bar style didn't match the design.** Rebuilt to Figma geometry: 58 pt bar
(was 68), 16 pt side inset, and a 66 pt centre button that sits *raised* — its
white ring breaks the bar's top edge by 13 pt with a teal glow beneath.
Previously a 56 pt button sat inline inside the bar, which read flat. Chats
badge is amber and overlaps the icon corner.
`HomeNavBar.reservedSpace(context)` now replaces the hand-tuned
`padding.bottom + 96` that screens used to reserve bottom space.

**Reels overlay was mispositioned.** The agency header sat in
`SafeArea > Padding > Row` with no `mainAxisAlignment`; the Row filled the
available height and centred itself vertically, so the name floated mid-screen.
It's now pinned top-centre. The action rail moved from `bottom: inset + 68` to
`top: 42%` of screen height on the right, and "Property details" is
right-aligned above the nav bar instead of centred — both per the frame.

**`ResultsScreen._goTab` ignored its argument.** It accepted a `NavTab` and
always returned to the Reels tab, so any nav tap from results reset the app.

**Fair-price gauge marker was hardcoded** to `Alignment(0.0, 0)` regardless of
price. It now reads `FairPrice.position` off the model.

**Detail screen content was hardcoded** — address, "4 people", "Both en-suite",
"3 years old", the amenity list and the description were string literals. All
now come from `Property`.

**Result count and chips were hardcoded** ("214 results", "Palm Jumeirah,
Dubai · 2 Beds"). All derived from the live `SearchQuery` and the controller's
`total`, so the filter footer and the results header can't disagree.

**Filters and sort did nothing.** They now return a `SearchQuery` /
`SortOption` via `Navigator.pop`, and the caller applies it. The Filters footer
count is a real repository query, debounced while dragging sliders — the same
call the results screen makes.

**Save hearts, currency switcher and market/language choices were inert.**
Hearts now persist across screens via `SavedListingsStore`; market and language
commit to `AppState` on Continue.

**"No homes match" was unreachable.** Was a standalone route with static copy;
now an embedded view the results screen shows when a query genuinely returns
nothing, with relax-suggestions derived from the active filters.

**`MainShell` opened on Reels.** Now opens on Home, matching the design's centre
button as the default destination — and avoiding a full-bleed media feed as the
first frame after onboarding.

---

## 6. Performance notes

The app must stay smooth on mid-range Android. What's in place:

- **Lazy + kept-alive tabs.** `MainShell` doesn't construct a tab until first
  visit, then preserves it (`AutomaticKeepAliveClientMixin`). Cold start pays
  for Home only.
- **`ListView.builder` everywhere**, with `cacheExtent` set. Results is a single
  builder with the header at index 0 and the footer at n+1, rather than building
  every card up front.
- **`cacheWidth` on every image.** `PropertyImage` decodes remote photos down to
  display width; category PNGs are capped at 144 px. Decoding a full-resolution
  listing photo into a 240 pt card is the most common source of dropped frames
  in an app like this.
- **Notifier granularity.** Tapping a heart repaints that heart. Swiping a reel
  or the gallery repaints the overlay, not the `PageView` (page index lives in a
  `ValueNotifier`, not `setState`). The search screen's typing flag and
  suggestions are separate notifiers.
- **`RepaintBoundary`** around the nav bar, centre button, images, the location
  graphic and the map painter.
- **Debouncing** — one suggest request per typing pause (280 ms), one filter
  count per slider pause (250 ms).
- **Const overlays** — gradient scrims use `const DecoratedBox` with literal
  `Color(0x…)` values rather than `withValues()` recomputed each build.

---

## 7. Known gaps and deliberate placeholders

Worth knowing before you assume something is broken:

1. **No listing photography.** None shipped with the handoff.
   `PropertyImage` renders a deterministic brand gradient keyed by a seed, so
   cards stay visually distinct. Pass `url:` and it fades in a network image
   with the gradient as fallback — call sites don't change.
   `GalleryScreen.itemsFor` is the equivalent seam for the Gallery: it
   synthesises tiles today and returns real media once `Property.photos` fills.
2. **Map is a `CustomPaint` grid**, isolated in `_MapPlaceholder` inside
   `property_detail_screen.dart`. Swapping in `google_maps_flutter` touches one
   widget. There is no Results map view yet.
3. **Reels are images, not video.** `Reel.mediaUrl` is plumbed through; a video
   player is not. Same for the Gallery's video tile and its 360° placeholder.
4. **No routing table.** Still `Navigator.push` with `MaterialPageRoute`. Works,
   but blocks deep links — the blueprint wants shareable listing URLs. Moving to
   `go_router` is the recommended next structural change.
5. **No i18n.** `Directionality` is wired and driven by `AppState`, but strings
   are hardcoded English. Adding `flutter_localizations` + ARB files is additive
   from here rather than a rewrite.
6. **Auth is frontend-only.** Round 3 built the full flow (screens 23–26) and
   the account surfaces, but `AuthController` holds no token and
   `verifyCode` accepts any six digits. The error paths and loading states are
   real and wired, so the swap is an `AuthRepository` behind the same seam —
   not a UI rewrite. Add the token and interceptor there, not in screens.
7. **Off-plan filters** (`offPlanPurpose`, `projectCompletion`,
   `prehandoverPayment`, `handoverYear`, `projectStatus`, `developer`) exist in
   `SearchQuery` and the UI, and serialise to query params, but the mock
   repository ignores them — there's no off-plan seed data.
8. **One widget test.** Boot-to-splash only. Controllers and the repository are
   pure Dart and easy to unit-test; that's the highest-value place to add
   coverage next. `CompareScreen._rows` and `MortgageScreen`'s amortisation are
   also pure functions and worth covering — both encode real judgement.
9. **Share targets are stubs.** They copy the link rather than firing an OS
   intent, because that needs `share_plus`. One callback to change.

---

## 8. Getting started

```bash
flutter pub get
flutter analyze      # do this first — the change set was not compiled locally
flutter run
```

Useful toggles while developing:

```dart
// main.dart — exercise the error states end to end
MockListingRepository(failEverything: true)

// tests — remove simulated latency
MockListingRepository(latency: Duration.zero)
```

## 9. Suggested next steps, in order

1. `flutter analyze`, fix anything it flags, commit as the baseline.
2. Add `shared_preferences`; hydrate and persist `AppState`.
3. Move to `go_router`; add deep links for listing detail.
4. Write `ApiListingRepository` against the real endpoints; keep the mock for
   tests. Add auth token handling and a refresh interceptor here.
5. Extract strings to ARB; test every screen in Arabic.
6. Replace `_MapPlaceholder` with a real map; build the Results map view.
7. Build the screens that don't exist yet — auth, chat, post-a-listing, seller
   dashboard, saved listings.

---

## 10. Round 2 additions — quick map

Added after the original handover. `CHANGES.md` has the reasoning; this is just
where to look.

| Screen | File | Entry point |
|---|---|---|
| Fair Price sheet | `screens/fair_price_sheet.dart` | Detail: verdict chip, gauge card, "How is this calculated?" |
| Compare | `screens/compare_screen.dart` | Fair Price sheet → "Compare the Property" |
| Mortgage estimate | `screens/mortgage_screen.dart` | Detail: "Estimate my mortgage" (sale listings only) |
| Share this home | `screens/share_sheet.dart` | Detail gallery share icon; Gallery share icon; Compare share icon |
| Photo Gallery | `screens/gallery_screen.dart` | Detail: tap hero photo, the 1/7 counter, or the 360°/Video tags |

Two shared pieces worth knowing about before you touch either screen:

- **`FairPriceGauge`** (public, in `fair_price_sheet.dart`) is used by both the
  sheet and the detail screen. One implementation means the marker can't sit in
  two different places for the same listing.
- **`CompareScreen._rows`** is the only place that decides which column "wins" a
  row. It is direction-aware — lower is better for money, higher for space —
  and returns null where there's no natural winner. Don't move that judgement
  into the cell widgets.

---

## 11. Round 3 — auth and account

See `CHANGES_ROUND3.md`. Entry points:

| Surface | File |
|---|---|
| Login tab (swaps on session) | `screens/main_shell.dart` -> `_LoginTab` |
| Sign-up flow | `login_screen` -> `email_login_screen` / `otp_screen` -> `purpose_screen` |
| Account home | `screens/profile_screen.dart` |
| Save gating | `widgets/sign_in_prompt.dart` |

Three rules to keep:

- **Never touch `SavedListingsStore` directly from a new save affordance.** Go
  through `SignInPrompt.gate` so the sign-in gate and hold-and-apply behaviour
  can't be forgotten in one place.
- **`AuthController` stays out of `AppState`.** `AppState` is watched app-wide;
  merging them makes every sign-in rebuild the tree.
- **`AppIcons` is the only place asset paths appear.** The Figma export renames
  and occasionally swaps glyphs between rounds.

---

## 12. Rounds 4 & 5 — offline, filters, chats

See `CHANGES_ROUND4.md`. Three rules added to the list in §11:

- **`PropertyCategory` is the only place category names live.** The Home grid and
  the Filters type dropdown both read it. Adding or renaming a category is a
  one-file change; hardcoding a list in a screen re-creates the bug where half
  the home page couldn't be filtered on.
- **Don't move the offline gate outside `MaterialApp.builder`.** It wraps the
  Navigator deliberately, so losing connectivity doesn't unwind the user's stack.
- **When `ApiListingRepository` lands, call
  `ConnectivityController.reportRequestFailure()` on request failure** — it
  triggers an early probe without assuming offline, so a real outage is noticed
  on the failed request rather than up to 8 seconds later.
