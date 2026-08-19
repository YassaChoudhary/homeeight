# CHANGES — round 2

Everything in this round came from the Figma frames in `Assets.zip`
(07, 08, 16–21) plus three reported issues. Read `DEVELOPER_HANDOVER.md` for
the architecture; this file is just what moved.

**Run `flutter analyze` before anything else.** There was no Dart toolchain
available where this change set was written, so it has not been compiled. It
has been checked for bracket balance and cross-file symbol resolution, which
catches structural breakage but not type errors.

---

## 1. Bugs fixed

### The home screen rendered totally white

Not a styling problem — a layout exception.

`_Hero` was `SliverToBoxAdapter > ClipRRect > PropertyImage`, and
`PropertyImage` is a `Stack(fit: StackFit.expand)`. A sliver hands its child
**unbounded** vertical constraints, and `StackFit.expand` tightens whatever it
receives onto its children — so the stack was asked to be infinitely tall.
That throws during layout, and because the hero is the *first* sliver, the
whole `CustomScrollView` failed to lay out. Result: a blank screen with no
visible error in release mode.

Every other `PropertyImage` call site in the app happens to sit inside a
bounded box (a grid cell with an aspect ratio, a `SizedBox`, a `PageView`),
which is why Home was the only screen affected.

**Fix:** the hero now declares its own height — `_Hero.contentHeight` (226,
taken from the Figma frame) plus the status-bar inset. Nothing about the
layering changed.

**Class of bug to watch for:** any `PropertyImage`, or anything else built on
`StackFit.expand`, placed directly in a sliver or an unconstrained `Column`
will do this again. If a screen goes blank, look for an unbounded box before
looking at colours.

### `studio.png` was the wrong illustration

`assets/images/categories/residential/studio.png` was byte-identical to
`villas.png` (both md5 `9dee7bed…`), so the Studio tile drew a villa. Replaced
with the real file from the new export (`c08532a9…`). Worth knowing the Figma
export has form here — see the `NavIcons` note in the handover for the two
SVGs that shipped under each other's names.

### Onboarding landed on Home instead of Reels

`LocationPermissionScreen._finish` now pushes
`MainShell(initialTab: NavTab.reels)`. `MainShell` still *defaults* to Home for
every other entry point, so this is the one explicit request rather than a
change to the shell's default.

---

## 2. Home screen — rebuilt to frames 07 / 08

`lib/screens/home_screen.dart` rewritten. Against the frames:

- **Hero** — full-bleed photo, three-stop scrim with `const` literal colours
  (not recomputed `withValues()`), city + chevron + bell, 26pt two-line
  greeting, glass search bar with a 46pt teal filter button. 28pt bottom
  corners.
- **For Rent / For Sale** — hug-width floating white pill, teal active segment
  with its own glow, centred. Uses the two new SVG glyphs.
- **Residential / Commercial** — full-width white card, **amber** active half
  (see §5), 58pt tall.
- **Category grid** — 3 columns, `0.80` aspect, white cards with shadows
  rather than borders, 52pt art, 13.5pt bold title over an 11pt subtitle.
  Titles that need two lines carry an explicit `\n` so they break where the
  Figma breaks them.
- Both carousels and the section headers match; `DealCard` was already right
  and is untouched.

The search bar now switches to the Search **tab** rather than pushing Results,
which is what the nav model implies.

---

## 3. New screens

| File | Frame | Notes |
|---|---|---|
| `screens/share_sheet.dart` | 17 | Listing preview, 4 targets, copyable link |
| `screens/fair_price_sheet.dart` | 18 | Money-labelled band, comparables, compare CTA |
| `screens/compare_screen.dart` | 19 | Two-column table with derived winners |
| `screens/mortgage_screen.dart` | 20 | Local amortisation maths |
| `screens/gallery_screen.dart` | 21 | Dark mosaic + fullscreen pager |

### Share sheet

Targets **copy the link and confirm with a snackbar** — a real hand-off needs
`share_plus` or `url_launcher`, and no dependencies were added. `_ShareTarget.onTap`
is the single place to swap in the real intent. The URL is built in
`ShareSheet.shareUrl` rather than inline, so it can become a backend-provided
canonical link without touching layout.

### Fair Price sheet

The comparables are a **repository call, not a prop**: the detail screen holds
a `Property`, but the evidence behind the verdict is a separate resource that
can be slow or empty independently, so the sheet owns its own
loading/error/empty branches.

Three things on the detail screen open it — the verdict chip, the gauge card,
and "How is this calculated?" — because they're all the same question.

`FairPriceGauge` is public and shared between the sheet and the detail screen,
so the two can't disagree about where the marker sits. It uses `LayoutBuilder`
to position the marker by pixel offset rather than `Alignment`, so the marker
never overhangs the track ends at position 0.0 or 1.0.

### Compare screen

**The green ticks are derived, never hardcoded per column.** `CompareScreen._rows`
computes a `winner` per row, and "better" is direction-aware: rent and
price-per-sqft win *low*, area and beds win *high*, and furnishing has no
natural winner so it gets no tick at all. That's what stops the two columns
disagreeing when real data lands.

The right column is a `ComparableListing`, not a full `Property` — that's all
the comparables endpoint returns. Fields it doesn't carry render as `—` rather
than being invented, and rows where either side is unknown are skipped for
tick purposes.

### Mortgage screen

Standard amortising payment computed locally — there's no endpoint and doesn't
need to be, since every input is on screen, and it keeps the slider
responsive. The zero-rate case is handled separately so a 0% preset can't
divide by zero. Rate presets are per-market (`_ratePresets`), matching the
frame's "Rate (UAE preset)" label. Entry point appears on **sale listings
only**.

### Gallery screen

- The mosaic is **deterministic** — one full-width hero then pairs — so the
  same listing always lays out the same way and scroll position survives
  filter changes.
- Filters are **client-side over an already-loaded list**, so switching chips
  needs no refetch and no loading state.
- `GalleryScreen.itemsFor` is the seam. No photography shipped, so when
  `Property.photos` is empty it synthesises deterministic gradient tiles
  seeded off the listing id — enough to exercise the real layout including the
  video and 360 tiles. Once photos arrive that branch stops being reached.
- The 360 tile is a dashed-outline placeholder, not media, and is excluded
  from the fullscreen pager.
- Tapping a photo on the detail hero opens the gallery *and* the viewer at
  that photo; Back returns to the grid.

---

## 4. Location permission — heartbeat pulse

`_LocationGraphic` is now stateful. One `AnimationController` drives
everything; the rings read the same animation at staggered phase offsets so
the wave travels outward rather than two circles breathing in unison.

`_beat` shapes the curve as a **two-thump cardiac envelope** (systole,
partial relaxation, second smaller beat, then rest) rather than a sine — that
is what makes it read as a pulse instead of a throb. The solid teal disc
scales least (4.5%) so the pin stays legible.

Only transforms, opacities and a shadow animate — no layout work per frame,
and the whole thing stays inside the existing `RepaintBoundary`.

---

## 5. Model, repository and theme changes

- **`FairPrice`** gained `bandLow` / `fairLow` / `fairHigh` / `bandHigh`
  (nullable), plus `hasBands`, `verdictLabel` and `verdictSentence`. Nullable
  so a backend returning only a verdict and position still renders — the sheet
  falls back to the unlabelled gauge.
- **`ComparableListing`** is new. Note the name: it is deliberately *not*
  `Comparable`, because that would shadow `dart:core`'s `Comparable<T>` across
  the whole model layer.
- **`ListingRepository.comparables(id)`** added → `GET /listings/{id}/comparables`.
  Implemented in the mock over new seed data; `p1` carries real band edges.
- **`AppState.marketCity`** added for the hero header. Placeholder per market
  until the backend resolves a city from device location.
- **`NavIcons`** gained `locationPin`, `purposeRent`, `purposeSale`.

### One theme change, flagged deliberately

`AppColors.amber` (`#F0A32C`) is new. The handover recorded `lib/theme/` as
untouched byte-for-byte; that is **no longer true**. The Figma
Residential/Commercial toggle reads distinctly more golden than
`accent` (`#E07A3C`), and the nav bar was already hardcoding `#F5A623` for the
Chats badge, so the token existed in spirit already. This is a judgement call,
not an accident — revert it to `accent` if you'd rather keep the palette
frozen.

---

## 6. Still open

Unchanged from the handover: no auth, no routing table, no i18n strings, no
real map, reels are images not video, off-plan filters serialise but the mock
ignores them, one widget test.

Added by this round:

1. **Share targets are stubs.** Add `share_plus` / `url_launcher` and fill in
   `_ShareTarget.onTap`.
2. **Video playback.** The gallery renders a video *tile* with a play button;
   tapping it opens the still. Needs `video_player`.
3. **360 tour.** Placeholder tile only.
4. **Compare is 1-vs-1.** The frame shows two columns; if you want 3-up,
   `_rows` needs to return a winner per row across N columns rather than a
   `_Side`.
5. **`GalleryScreen.itemsFor` invents room groupings** (`Living`, `Bedrooms`,
   `Exterior`) by cycling a list, because listings carry no per-photo
   metadata. The filter chips are only meaningful once the backend tags media.
6. **Mortgage pre-approval** button shows a snackbar.
