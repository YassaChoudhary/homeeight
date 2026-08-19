# CHANGES — round 3 (auth + account)

**Run `flutter analyze` first.** No Dart toolchain was available here, so this
is uncompiled. Verified for bracket balance, duplicate top-level names,
cross-file symbol resolution and unused imports — that catches structural
breakage, not type errors.

---

## 1. Icons replaced

All 17 SVGs from the new export are installed under names that say what they
draw, and referenced through `lib/widgets/app_icons.dart` — same reasoning as
`NavIcons`: this export has a history of unhelpful names
(`Group 1171275372.svg`) and, in an earlier round, two glyphs shipped under
each other's names. A future re-export only needs fixing in one file.

Identification took a few passes because most of these have `fill="none"` with
no stroke colour, so they render blank until a stroke is forced.

| Installed as | Was | Replaces |
|---|---|---|
| `bell.svg` | Homescreen/Vector-1 | `Icons.notifications_none_rounded` in the Home hero |
| `pin_small.svg` | Homescreen/Vector | `NavIcons.locationPin` beside the city |
| `filter_sliders.svg` | search screen/SVG-1 | `Icons.tune_rounded` on the hero filter button |
| `sort_arrows.svg` | search screen/SVG | sort control |
| `control_divider.svg` | search screen/Vector | filter/sort divider |
| `tour_360.svg` | Property/Group 1171275381 | `Icons.threed_rotation_rounded` on the 360° tag |
| `contact_email.svg` | Property/Group 5141721 | `Icons.mail_outline_rounded` |
| `contact_call.svg` | Property/Path 44186 | `Icons.call_rounded` |
| `contact_whatsapp.svg` | Property/WA_Logo | `Icons.chat_rounded` |
| `compare_arrows.svg` | Property/SVG | new, on the Compare CTA |
| `purpose_find.svg` | login/Group 1171275372 | Find a Property |
| `purpose_list.svg` | login/Group 1171275371 | List a property |
| `auth_phone.svg` / `auth_email.svg` | login/SVG-1, SVG | provider buttons |
| `globe.svg` | login/SVG-2 | Language & market |
| `heart_solid.svg` | login/Vector | Saved Items, saved-card heart |
| `saved_empty.svg` | login/Group 1171275382 | "Nothing saved yet" graphic |

**One flag:** `Homescreen icon/SVG.svg` renders as up/down **sort arrows**, not
the sliders you'd expect for the hero's filter button. I mapped sliders →
filter, arrows → sort. Say so if that's backwards. Also `purpose_rent.svg` /
`purpose_sale.svg` from round 2 were my guesses for the Home For Rent/For Sale
toggle and are still unconfirmed.

---

## 2. Auth — frontend only, by design

`lib/state/auth_controller.dart`: `AuthUser`, `AuthMethod`, `UserIntent`,
`AuthController`, `DialCode`.

There is no token, no expiry and no server call. **`verifyCode` accepts any six
digits.** It still returns a `bool`, and every screen's error path is built and
wired, so those paths work unchanged once there's something real to verify
against. Same reasoning for the simulated latency: button loading states get
exercised now rather than discovered later.

`AuthController` is a **separate notifier from `AppState`**. `AppState` is
watched by nearly every screen for market and language, so putting the session
in it would rebuild the whole tree on sign-in — the same reason
`SavedListingsStore` is separate.

When the backend lands: `AuthUser` gains the tokens, and the mock branches
become calls behind an `AuthRepository` shaped like `ListingRepository`.

---

## 3. Screens built

### Auth flow (23 → 26)

| Screen | File |
|---|---|
| Login or sign up (phone) | `screens/login_screen.dart` |
| Continue with Email | `screens/email_login_screen.dart` |
| Enter your code | `screens/otp_screen.dart` |
| What brings you to Home8? | `screens/purpose_screen.dart` |

**Login is a real tab, not a pushed route.** `MainShell` now keeps `NavTab.login`
in its `IndexedStack` and `_LoginTab` swaps between `LoginScreen` and
`ProfileScreen` on session state. Signing in or out changes the tab contents in
place — no navigation, no flash of the wrong screen, and the nav bar never
rebuilds. It previously pushed `ComingSoonScreen`.

**The OTP screen uses one hidden field behind six painted boxes**, not six
fields. Six real fields means six focus nodes, hand-rolled backspace, and
broken SMS autofill; one field with `autofillHints: [oneTimeCode]` gets OS
autofill, caret and paste for free. It auto-submits on the sixth digit.

**Only "Find a Property" proceeds.** Selecting *List a property* shows a
work-in-progress snackbar and leaves the selection unchanged — there's no
post-a-listing flow, seller dashboard or agent onboarding to hand off to, so
committing to that intent would strand the user. The intent is still a real
value on `AuthUser` and the radio still renders, so enabling it later means
deleting the guard in `_select`, not rebuilding the screen.

The Google mark is **drawn as arcs**, not shipped as an asset — Google's brand
terms don't permit redistributing the logo file in a repo. Swap in the official
asset if you licence it.

### Account (F01–F09)

| Screen | File |
|---|---|
| Profile | `screens/profile_screen.dart` |
| Saved (Properties / Reels) | `screens/saved_screen.dart` |
| Edit profile | `screens/edit_profile_screen.dart` |
| Settings | `screens/settings_screen.dart` |
| Currency & region sheet | `screens/settings_screen.dart` |
| Help & support | `screens/help_support_screen.dart` |
| Notifications | `screens/notifications_screen.dart` |
| No connection | `screens/no_connection_screen.dart` |

Notes worth carrying forward:

- **Saved resolves ids through the repository.** `SavedListingsStore` holds only
  a `Set<String>` so the heart stays cheap everywhere; this screen hydrates them
  on open. There's no `GET /saved-listings` returning full records yet, so it
  sweeps rent and sale searches and filters client-side — that becomes one call
  later and nothing else changes.
- **Unsaving from the Saved grid keeps the card on screen** until you leave.
  Dropping the row instantly is what people complain about.
- **Unavailable listings dim rather than disappear** — silently removing a home
  someone saved is worse than showing it as gone.
- **Notification channels and topics are separate concerns.** Turning off every
  channel does not clear the topics, because the topics are still what you'd
  want if you re-enabled a channel.
- **Edit profile edits a local copy** and writes on Save, so backing out
  discards. "Verified" is flat text and "Confirm" is a button — one is a fact,
  the other a request only the backend can fulfil.
- **Dark theme stores the preference but doesn't change the palette.**
  `AppTheme.dark` doesn't exist. Wire `AppState.darkTheme` into
  `MaterialApp.themeMode` once one is designed.
- **No connection isn't wired to real connectivity** — that needs
  `connectivity_plus`. `onRetry` and `onViewSaved` are injected so the caller
  decides what they mean. `OfflineBanner` is public and can sit above any list.

---

## 4. Save gating (the queued item)

`lib/widgets/sign_in_prompt.dart`. `SaveHeartButton` now routes every tap
through `SignInPrompt.gate`.

**Hold-and-apply**, as agreed: the tap is not discarded. `gate` takes the action
and runs it after a successful sign-in, so the listing the user reached for gets
saved without them having to find it again. `PurposeScreen._finish` unwinds the
auth stack and invokes the callback rather than pushing the shell.

Use `SignInPrompt.gate` for any new save affordance rather than touching
`SavedListingsStore` directly, so the gate can't be forgotten in one place.

---

## 5. Model and state additions

- **`Property.previousPrice`, `available`, `unavailableReason`** plus
  `priceDrop` / `hasPriceDrop`, for the Saved screen's price-drop badge,
  struck-through old price and "No longer available" state. `previousPrice` is
  nullable — null means *no recorded change*, not *no change*. Price **rises**
  are deliberately not badged.
- **`AppState`** gained `pushEnabled`, `emailEnabled`, `smsEnabled`,
  `darkTheme` and `notifTopic(key)`. All local; becomes
  `PATCH /me/preferences`.
- **`AppScope`** now carries `auth`, reachable via `AppScope.authOf(context)`.

---

## 6. Still open

Carried over: no routing table, no i18n strings, no real map, reels are images
not video, off-plan filters serialise but the mock ignores them, share targets
copy instead of firing an intent.

New this round:

1. **Saved Reels tab is an honest empty state.** `SavedListingsStore` keys on
   listing ids and `Reel` has its own id space, so there is nothing to resolve.
   Needs a `savedReels` notifier and `GET /saved-reels`.
2. **Help & support content is static copy.** No help CMS; the search field says
   so when tapped rather than pretending to search nothing.
3. **These are stubs behind snackbars:** photo upload, password change, phone/
   email verification, agent onboarding, account deletion, privacy, blocked
   users, terms, quiet hours, support chat, help articles.
4. **`AppState` and the session still don't persist.** Adding
   `shared_preferences` now covers market, language, settings toggles *and*
   session restore — it went from a nice-to-have to the thing that makes login
   feel real, since right now every cold start signs you out.
5. **No password auth path.** Edit profile shows a password field because the
   frame does, but the flow is code-based only. Decide whether password is real
   before wiring the backend.
