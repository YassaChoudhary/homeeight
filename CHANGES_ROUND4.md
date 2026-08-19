# CHANGES — rounds 4 & 5 (offline detection, filters, chats)

**Run `flutter analyze` first.** No Dart toolchain was available where this was
written, so it is uncompiled. Verified for bracket balance, duplicate top-level
names, cross-file symbol resolution, unused imports, and that every referenced
asset path exists on disk.

No new dependencies. Still `cupertino_icons` and `flutter_svg` only.

---

## 1. Offline detection — now live

The No connection screen existed since round 3 but was never wired to anything.

**New:** `lib/state/net_probe.dart`, `net_probe_io.dart`, `net_probe_stub.dart`,
`connectivity_controller.dart`
**Changed:** `lib/main.dart`, `lib/screens/no_connection_screen.dart`

`ConnectivityController` polls a TCP socket against a public DNS resolver and
exposes `ValueNotifier<bool>`. `OfflineGate` sits inside `MaterialApp.builder`
and shows `NoConnectionScreen` over the app when that goes false.

### The gate wraps the Navigator rather than replacing it

Going offline does not unwind the navigation stack. The listing the user was
reading stays mounted underneath, and when the connection returns they are
exactly where they were rather than back at splash. The cost is that the gate
cannot push routes itself — being above the `Navigator` means
`Navigator.of(context)` finds nothing — which is why "View saved homes" goes
through a `navigatorKey`. That link works offline precisely because saved homes
are the one thing that doesn't need the network.

### Four deliberate behaviours

- **Two consecutive failures to go offline, one success to come back.** Mobile
  networks blip constantly — cell handovers, lifts, Wi-Fi roams. A single failed
  probe triggering a full-screen takeover would flash the offline screen several
  times an hour on a usable connection. Being slow to *recover* is the worse
  error, so recovery is immediate.
- **Interval adapts:** 8s online to stay off the battery, 3s offline so recovery
  feels instant.
- **Polling stops while backgrounded.** Probing from the background wakes the
  radio for nothing; state is rechecked on resume via
  `didChangeAppLifecycleState`.
- **No overlay until the first probe returns** (`hasResult`), so the app never
  flashes the offline screen at launch before anything has been measured.

### Why a socket rather than an HTTP request

There is no HTTP client in the dependency list. A socket to port 53 is a few
bytes and performs no DNS lookup of its own, so it cannot be fooled by a cached
DNS answer the way `InternetAddress.lookup` can. Two resolvers are tried
(1.1.1.1, then 8.8.8.8) because some corporate and captive networks block one
but not the other.

### Two limits

- **This reports reachability, not whether the API is up.** A captive portal that
  accepts TCP on 53 reads as online. Once `ApiListingRepository` exists, probe
  your own health endpoint and keep this as the fallback.
  `reportRequestFailure()` is already there for the repository to call — note it
  triggers an early probe rather than assuming offline, because a 500 from a
  healthy server is not a connectivity problem.
- **Web is a stub that always reports online.** `dart:io` doesn't exist there, so
  `net_probe.dart` conditionally exports the socket version on mobile/desktop and
  a stub on web. That conditional is what keeps `flutter build web` compiling.
  Real web support needs `navigator.onLine` plus the online/offline window
  events, or `connectivity_plus`.

**Testing:** airplane mode on with the app in the foreground — the screen appears
within ~6s (two failed probes at the 3s cadence). Drop `_failuresToGoOffline` to
1 in `connectivity_controller.dart` to iterate faster.

---

## 2. Property categories — one source of truth

**New:** `lib/models/property_category.dart`
**Changed:** `lib/screens/home_screen.dart`, `lib/screens/filters_sheet.dart`,
`lib/models/search_query.dart`

The Home grid and the Filters sheet each had their own hardcoded list. The grid
said `Studio`; the filter said `Studio (Studio & 1 BHK)`. Worse, the filter
listed **five** residential types against Home's nine and **no commercial types
at all** — so most categories on the home page could never be filtered on.

`PropertyCategory` is now the single source of truth for both. Adding a category
is a one-file change.

Each entry separates `title` (what the user reads) from `wire` (what
`SearchQuery.propertyType` stores and sends as `type=`), so display copy can
change without breaking a saved search or a deep link. `gridTitle` carries the
explicit line break the narrow grid tiles need.

An **Any** option was added at the top of the dropdown. The old code fell back to
`_propertyTypes[1]`, so the sheet always looked like Apartment was selected and
there was no way to clear a type once set.

### New "Property Nature" filter

Residential / Commercial pills sit directly above Property Type, mirroring the
Home toggle. Writes to `SearchQuery.segment`, which already existed and already
serialised.

**The important part is the invalidation.** Switching nature clears the selected
type when that type doesn't belong to the new nature — "Offices" is meaningless
once you're browsing residential. Without it the dropdown would read "Any" while
the query still filtered on `office`, returning zero results with no visible
cause. `PropertyCategory.lookup` returns null on a segment/type mismatch, which
is what drives the check.

Reset keeps nature and clears type: nature is a mode, type is a filter.

### Two supporting changes

- `SearchQuery.copyWith` gained a `clearPropertyType` flag. `copyWith` cannot
  distinguish "leave alone" from "set to null", so clearing a nullable field
  needs an explicit flag — same pattern as the existing `clearBeds` /
  `clearBaths`.
- `SearchQuery.activeChips` shows the display title for a type rather than the
  raw wire value. A results chip reading `bed_space` is a leak.

### One thing to know

`search_query.dart` and `property_category.dart` import each other — the
catalogue needs `PropertySegment`, the chips need `titleForWire`. Dart permits
circular imports between libraries and there is no circular constant
initialisation here, so it compiles. To avoid it, move `PropertySegment` into
`property_category.dart` and re-export.

---

## 3. Chats

**Changed:** `lib/widgets/home_nav_bar.dart`,
`lib/screens/coming_soon_screen.dart`, `lib/screens/main_shell.dart`

The hardcoded `3` badge is gone — `HomeNavBar.chatBadge` defaults to `0`, which
hides the badge. The parameter stays so a real unread count can be passed once
messaging exists. It previously read as three real unread messages sitting behind
a screen that doesn't exist.

`ComingSoonScreen` now **requires** a `message`. Defaulting it would let the next
caller ship a generic "coming soon" that tells the user nothing and the next
developer even less about what is missing. The Chats tab passes copy that names
the working alternative — Email, Call or WhatsApp on any listing — because a dead
end that tells you what to do instead is a different experience from one that
doesn't.

---

## 4. Still open

Carried over: no routing table, no i18n strings, no real map, reels are images
not video, off-plan filters serialise but the mock ignores them, share targets
copy instead of firing an intent, auth is frontend-only.

Highest-value next steps, in order:

1. **`shared_preferences`.** Nothing persists — market, language, settings
   toggles, saved hearts and the session all reset on cold start, which means
   every launch signs the user out. This went from a nice-to-have to the thing
   that makes login feel real.
2. **`ApiListingRepository`** against the real endpoints, with the auth token and
   refresh interceptor in that layer. Point
   `ConnectivityController.reportRequestFailure()` at it while you're there.
3. **`go_router`** and deep links for listing detail.
4. **Unit tests for the pure logic** — `CompareScreen._rows`,
   `MortgageScreen`'s amortisation, `SearchQuery.toQueryParameters`,
   `PropertyCategory.lookup`. All pure Dart, all encode real judgement.
