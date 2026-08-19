# Home8 — Handover Brief for the Next Assistant

You are picking up an in-progress Flutter app. The user (Essa — founder,
designer, and the one directing this build) will ask you to build **more UI
screens**. This document tells you what exists, the conventions to follow, and
where the Supabase work stands.

Read the whole thing before writing code. Most mistakes here come from not
knowing a helper already exists.

---

## 0. How to work with this user

Things that have mattered so far:

- **He wants whole files, not diffs.** When sharing code, paste the complete
  file with its full path (e.g. `lib/screens/foo_screen.dart`). This is a
  standing preference.
- **Plain language.** He has asked more than once for simpler wording. Skip the
  lecture; give the answer, then the reasoning briefly.
- **Deliver the whole project folder as a zip** when a change spans files. He
  unzips over his working copy at `C:\Users\yassa\Desktop\homeeight-main`.
- **He's on Windows / PowerShell / Android Studio**, testing on a physical
  Infinix Android phone. PowerShell writes UTF-16 by default — this already
  cost an hour when `env.json` came out unreadable. If you ever have him create
  a file from the terminal, use
  `[System.IO.File]::WriteAllText("$PWD\file", $text)`, or just have him do it
  in Android Studio.
- **He must run with the env file:**
  `flutter run --dart-define-from-file=env.json`. Plain `flutter run` silently
  falls back to mock data.
- **Push back when it matters.** He has changed direction based on pushback
  (nine Supabase projects → one; auto-switching market by GPS → market stays
  user-chosen). Say what you'd do differently and why, once, then follow his
  call.
- **You cannot compile.** Nothing in this environment can run `flutter`. Say so
  rather than claiming code is verified, and tell him to run `flutter analyze`.

---

## 1. What the app is

Home8 — a property marketplace for UAE / KSA / Pakistan and six other markets.
Built from a Figma handoff plus a 43-page product blueprint (`Home8 — Product
Blueprint & Build Specification`, which he can re-share; it defines 65 screens,
MVP/V1/V2 phasing, the data model and the API contracts).

The differentiators, in the blueprint's words: BUA (built-up area) as a
first-class search dimension, visible verification badges, one account spanning
markets and currencies, and an AI fair-price band.

**Stack:** Flutter (Dart SDK `^3.11.1`). ~17,000 lines across 62 Dart files.
Dependencies: `cupertino_icons`, `flutter_svg`, `supabase_flutter`,
`shared_preferences`, `geolocator`, `geocoding`. No state-management package, no
router package, no HTTP client — all deliberate, see §4.

---

## 2. Project layout

```
lib/
├── main.dart                    entry; Supabase init, Prefs load, repo choice
├── core/
│   ├── async_value.dart         AsyncValue<T> union + RepositoryException
│   └── env.dart                 build-time config (--dart-define)
├── models/
│   ├── property.dart            Property, Agent, FairPrice, Community,
│   │                            SearchSuggestion, Reel, formatters, gradients
│   ├── property_category.dart   residential/commercial category grids
│   └── search_query.dart        SearchQuery, SortOption, ListingPage
├── data/
│   ├── listing_repository.dart       ABSTRACT — the backend seam
│   └── mock_listing_repository.dart  in-memory impl with real filtering
├── state/
│   ├── app_scope.dart           Market, AppLanguage, AppState,
│   │                            SavedListingsStore, AppScope, AppStateBuilder
│   ├── auth_controller.dart     session (still mock — see §6)
│   ├── listings_controller.dart ListingsController, AsyncController<T>
│   ├── connectivity_controller.dart  online/offline
│   ├── location_service.dart    geolocator + geocoding wrapper
│   ├── prefs_store.dart         shared_preferences wrapper
│   └── guest_migration.dart     guest data → account on sign-in
├── theme/                       tokens — DO NOT hardcode colours/sizes
├── widgets/                     shared components (see §3)
└── screens/                     32 screens
```

---

## 3. Components that already exist — use these, don't rebuild

This is the section that saves you the most time.

### Buttons — `widgets/pill_button.dart`
- `PrimaryButton` — teal pill, **full width by default**, has `loading`,
  `expand`, `glow`, `leadingIcon`, `trailingIcon`
- `GhostButton` — outlined pill on white
- `TertiaryButton` — bare text ("Not now", "Skip")
- `OverlayPillButton` — translucent, for use over imagery
- `Pressable` — press-scale wrapper; the theme disables Material ink, so **every
  tappable thing needs this or a GestureDetector**
- `SheetDragHandle`

### Cards — `widgets/listing_card.dart`
- `DealCard` — horizontal carousels. **Fixed geometry published as constants:**
  `DealCard.height` (252), `DealCard.imageHeight` (150), `defaultWidth` (240).
  Size carousels from `DealCard.height` — a mismatch here caused a
  "BOTTOM OVERFLOWED BY 47 PIXELS" bug.
- `ResultListingCard` — full-width results row
- `SaveHeartButton` — already gated behind sign-in
- `VerifiedPill`, `ListingBadge`

### States — `widgets/state_views.dart`
- `SkeletonBox`, `DealCardSkeleton`, `ResultCardSkeleton`
- `ErrorStateView` (has `onRetry`), `EmptyStateView`

**Every async surface must render all three branches** — loading, data, error.
This is non-negotiable in this codebase; a blank screen on a slow connection is
treated as a bug.

### Other
- `widgets/property_image.dart` — `PropertyImage(seed:, url:, decodeWidth:)`.
  No photography shipped, so it falls back to a deterministic brand gradient.
  **Always pass `decodeWidth`** — see §8.
- `widgets/home_nav_bar.dart` — `HomeNavBar`, `NavTab` enum, `NavIcons`.
  Use `HomeNavBar.reservedSpace(context)` for bottom padding on scrolling
  screens; never hardcode a number.
- `widgets/brand_mark.dart` — `BrandMark(BrandLogo.google)` / `.apple`.
  Use on any auth surface. Never apply a colour filter (brand terms).
- `widgets/sign_in_prompt.dart` — `SignInPrompt.gate(...)` and
  `.gateListing(...)`. See §7.
- `widgets/app_icons.dart` — all SVG paths as constants.

### Theme — `theme/`
`AppColors` (primary `#12A0A2`, accent, amber, ink, inkMuted, line, surface, bg,
navDark), `AppSpacing` (4-pt scale), `AppRadius`, `AppTextStyles`
(display/h1/h2/body/bodyStrong/caption/micro, Circular Std).

**Never hardcode a hex or a font size.** If a token doesn't exist for what the
design shows, say so rather than inlining a value.

> Note: `AppColors.primary` is `#12A0A2`, not the blueprint's `#0D5C63`. The
> code follows the Figma mocks. This is intentional — don't "fix" it.

---

## 4. Architecture — the four layers

### Repository — the backend seam
`ListingRepository` (abstract, 10 methods) is the **only** thing any screen
knows about data. Method names mirror blueprint §9.3 (`search()` →
`GET /search`, etc.). `MockListingRepository` implements it with real filtering,
sorting, pagination and 350ms simulated latency.

**When you add a screen that needs data, add a method to the interface and
implement it in the mock.** Never import mock data into a screen.

### Controllers — `state/listings_controller.dart`
- `ListingsController` — owns a query + paged results + loading/error flags,
  debounced `setTerm`, cancels stale responses by request id
- `AsyncController<T>` — one-shot loads (highlights, communities, detail)

### Scope — `state/app_scope.dart`
A plain `InheritedWidget`. Deliberately not provider/riverpod — swapping later
means editing one file.

```dart
AppScope.watch(context)        // read + subscribe (in build)
AppScope.of(context)           // read, no subscribe (callbacks/initState)
AppScope.repositoryOf(context)
AppScope.savedOf(context)
AppScope.authOf(context)
AppStateBuilder(builder: ...)  // rebuild only this subtree
```

`AppState` is kept small on purpose — every listener rebuilds when it changes.
High-frequency things (saved hearts, page indices) live in their own
`ValueNotifier`s.

### Persistence — `state/prefs_store.dart`
`shared_preferences`, loaded once in `main()` before `runApp`, so the splash
screen routes without a disk wait. All keys namespaced `h8.`.
`AppState.restore()` reads it; every setter writes back via `_persist`.

---

## 5. Supabase — where it stands

**Project:** `home8 Project`
**URL:** `https://bageehfzmwuyfaehaaon.supabase.co`
**Region:** Central EU (Frankfurt) — chosen for latency to Dubai
**Plan:** Free
**Settings at creation:** Data API ✅ · auto-expose new tables ❌ · automatic
RLS ✅

### What's done
Step 1 only: **the app connects.** `supabase_flutter` is installed,
`Supabase.initialize()` runs in `main()`, and the console prints
`Supabase initialised: https://bageehfzmwuyfaehaaon.supabase.co`.

Config is in `lib/core/env.dart`, read from `--dart-define`. Credentials live in
`env.json` (git-ignored); `env.example.json` is the committed template.
`Env.hasSupabase` gates initialisation, and a missing key means the app runs on
mock data instead of crashing.

### What is NOT done
- **No tables.** The database is empty.
- **No RLS policies.**
- **No auth.** `AuthController` is still a mock — any six digits pass, no token,
  no session restore, no refresh.
- **No real reads or writes.** Every screen still uses
  `MockListingRepository`.
- **No storage.** No listing photography exists at all.

### Decisions already made (don't relitigate)
- **One Supabase project, not nine.** A `market` column on every table plus RLS.
  Nine projects would cost 9×, and Supabase auth pools don't span projects —
  which would break the "one account across countries" selling point. If legal
  later requires one market in-region, split *that one* out; the `market`
  column makes the rows cleanly separable.
- **Auth before tables.** Every RLS policy keys off `auth.uid()`. Build tables
  first and you write the policies twice.
- **Media:** photos → Supabase Storage initially, move to Cloudflare R2 if
  egress bites. Reels video → **Cloudflare Stream**, because Supabase Storage
  can't transcode or do adaptive bitrate, and a 40MB download on weak 4G makes
  the feed feel broken. Not urgent — there's no media to upload yet.
- **The anon key is publishable, not secret.** RLS is the security boundary.
  The `service_role` key must never appear in the app.

### The next Supabase steps, in order
1. Enable a provider (phone OTP needs an SMS vendor — Twilio/MessageBird/Vonage
   — and sender-ID approval in UAE/KSA; **email is faster to get working** and
   the email login screen already exists).
2. Rebuild `AuthController` on `supabase.auth.onAuthStateChange`.
3. Schema + RLS policies, written together.
4. `SupabaseListingRepository implements ListingRepository`; swap the one line
   in `main.dart`.
5. Hydrate `SavedListingsStore` from the server.
6. Writes + Storage, which unblocks the post-a-listing flow.

Step 4 is close to mechanical because of the seam. Steps 1–3 are the real work.

---

## 6. Guest state and the migration path

Guests can use the whole app without an account. Their state lives **on the
phone**, not the server — reading it must be instant and work offline, and a
network call on the splash screen would mean a spinner on a weak connection.

Stored locally: market, language, currency, onboarding-seen, location answer,
detected city/country, recent searches, notification prefs.

**`state/guest_migration.dart`** snapshots all of it the moment sign-in succeeds
and parks it as a pending payload, then uploads. Capture and upload are separate
steps on purpose: a failed upload leaves the payload on the device to retry next
launch rather than losing it. `GuestMigration._upload()` has a TODO with the
exact Supabase call to drop in once a `profiles` table exists.

**Saved listings are not in the payload** — saving already requires an account,
so a guest can't accumulate any. If that rule ever changes, add them and merge
server-side rather than replacing.

---

## 7. Behaviour rules to preserve

**Saving and listing require an account.** Both go through
`SignInPrompt.gate(...)` / `.gateListing(...)`, which **holds the intent** — the
user lands back on the action they were reaching for after signing in, not on a
blank profile screen. If you add any new save or post affordance, route it
through the gate; never touch `SavedListingsStore` directly.

**Location and market are independent.**
- Location = where the user physically is → drives `AppState.headerCity` only
- Market = whose listings they're browsing → chosen in onboarding/settings
- Someone in Lahore with UAE selected sees "Lahore" in the hero and UAE
  properties below, plus an explanatory note
- `applyDetectedPlace()` deliberately does **not** change the market

**The app opens on Reels**, even though Reels sits second in the nav bar. The
two are independent by design; there's a comment saying so in `MainShell` so
nobody "fixes" it.

**The nav bar centre button is an action, not a destination.** It's `+` (post a
listing) via `onPost`, not a `NavTab`. Making it a tab would deselect whatever
tab was underneath.

**Only UAE has listings.** `Market.isLaunched` is true for UAE alone. Screens
that could show an empty market should say "launching soon" rather than
rendering zero results.

---

## 8. Performance conventions

The target is mid-range Android on 4G. Follow these:

- `ListView.builder` / `SliverList` always; never build a full list up front
- **`cacheWidth` on every image** — decoding a full-res photo into a 240pt card
  is the most common source of dropped frames here. `PropertyImage` takes
  `decodeWidth`; pass it.
- Tabs build lazily and keep alive (`AutomaticKeepAliveClientMixin`)
- Fine-grained notifiers — page indices and toggles use `ValueNotifier` +
  `ValueListenableBuilder`, not `setState` on a whole screen
- `RepaintBoundary` around nav bars, images, custom painters
- Debounce anything typed or dragged (280ms for search, 250ms for filter counts)
- `const` for gradient scrims and static decoration

---

## 9. Screens: built vs. not

**Built (32):** splash, onboarding, choose market, select language, location
permission, main shell, home/discover, search, results, filters sheet (standard
+ off-plan), sort sheet, no results, property detail, gallery, fair price sheet,
mortgage, compare, share sheet, reels, saved, notifications, profile, edit
profile, settings, help & support, login, email login, OTP, purpose, no
connection, coming soon.

**Not built — likely what he'll ask for next:**
- **Post a listing** — a multi-step stepper (blueprint screens 28–36: start,
  location, details, price, media, permit/verification, preview, promote,
  submitted). Currently `openPostListingFlow()` shows a placeholder. This is the
  biggest gap.
- **Chat** — inbox + thread (screens 26–27); the nav tab shows a placeholder
- **Seller/agent dashboard** — my listings, stats, leads (37–39)
- **Agent public profile** (40)
- **Saved searches** (45), notification settings (47)
- **Map view of results** (15) — `_MapPlaceholder` in the detail screen is a
  `CustomPaint` grid; no map SDK is wired anywhere
- **Admin console** (55–62) — web, out of scope for the app

---

## 10. Known gaps — don't mistake these for bugs

1. **No listing photography.** Gradients are the intended fallback.
2. **Map is fake** — isolated in `_MapPlaceholder`, one widget to swap.
3. **Reels are images, not video.** `Reel.mediaUrl` is plumbed; no player.
4. **No routing table** — still `Navigator.push` with `MaterialPageRoute`.
   Works, but blocks deep links. `go_router` is the recommended next structural
   change.
5. **No i18n.** `Directionality` is wired and driven by `AppState`, so Arabic
   flips the whole tree, but strings are hardcoded English.
6. **Bundle ID is still `com.example.homeeight`** — Play Store rejects
   `com.example.*`. Must change before release; it's more than find-and-replace
   (Kotlin package path on Android, Xcode on iOS).
7. **`name: homeeight` in pubspec** is the Dart package name — every
   `import 'package:homeeight/...'` depends on it. Not worth renaming.
8. **One widget test.** Boot-to-splash only. Controllers and the repository are
   pure Dart and are the highest-value place to add coverage.

---

## 11. When you build a new screen — the checklist

1. Read the Figma image he provides carefully; match spacing and hierarchy, not
   just content.
2. Use existing components (§3). Add to `widgets/` only if genuinely reusable.
3. Tokens only — no hardcoded colours, sizes or radii.
4. If it needs data: add a method to `ListingRepository`, implement it in the
   mock, drive the screen with `AsyncController` or `ListingsController`.
5. Render loading / data / error. Always.
6. Bottom padding from `HomeNavBar.reservedSpace(context)` if it scrolls behind
   the bar.
7. Gate any save/post action through `SignInPrompt`.
8. Comment the *why* for non-obvious decisions — this codebase is
   heavily commented and he passes it to other developers.
9. Deliver the full file with its path; zip the project if several files change.
10. Remind him to run `flutter analyze` — you cannot compile.

---

## 12. Other docs in the repo

- `DEVELOPER_HANDOVER.md` — written for a human developer; overlaps with this
- `SUPABASE_SETUP.md` — the connect step, env.json instructions, key hygiene
- `CHANGES.md`, `CHANGES_ROUND3.md`, `CHANGES_ROUND4.md` — history of earlier
  rounds, including bug causes worth not repeating

If something here contradicts the code, the code wins — and tell him, so this
document gets fixed.
