# Supabase setup — listings and search

Supabase project: `https://bageehfzmwuyfaehaaon.supabase.co`

## How the two backends split

| Firebase (`home8-61d48`) | Supabase |
|---|---|
| Login: Google, email code (Firebase custom token) | Listings, search, filters, map area search |
| User records (`users/{uid}`) | Saved listings (hearts) |
| Chat, push notifications (next) | Similar homes, comparables, highlights |
| | Communities, autocomplete, reels feed |
| | `email-auth` Edge Function (sends/checks email codes) |

**There is one login — Firebase.** The app sends the Firebase ID token to
Supabase; Supabase verifies it and Row Level Security uses the Firebase user id.
Users never sign in to Supabase separately.

What reads from Supabase now: Home, Search, autocomplete, Results (all filters
and sorts), Property detail, Similar homes, Fair Price comparables, Reels feed,
Saved hearts. **Still on mock data:** the seller side (My Listings, posting,
stats) — it moves over together with photo upload in the next step.

---

## Setup
See **SETUP.md** (Part C). This file explains how the Supabase side works.

## Checking it works
- Console shows `Supabase initialised: https://bageehfzmwuyfaehaaon.supabase.co`.
- Change a price in Supabase → **Table Editor → listings**, pull to refresh in
  the app → the new price shows.
- Sign in, tap a heart → a row appears in **saved_listings** with your Firebase
  uid in `user_uid`.

If hearts don't save: the token is missing `role: authenticated`. Check that
third-party auth (SETUP.md C4) and the `email-auth` function (C3) are set up,
then sign out and in again.

## Security model (RLS)
- `public.firebase_uid()` returns the Firebase user id only for tokens issued by
  project `home8-61d48` (checks `iss` and `aud`); anything else is anonymous.
- Everyone can read **live** listings, agents, places and reels of live listings.
- Owners see and edit their own listings in any status, but **cannot set
  `live` themselves** — publishing happens in review (dashboard / service role).
- Saved listings: each user sees and changes only their own rows.

## Tests
`supabase/tests/tests.sql` — 49 checks (every filter, sort, paging, map bounds,
autocomplete, and the security rules for anonymous users, two different users
and a token from a different Firebase project). Run against a local Postgres
after `supabase_stub.sql`, the migration and the seed.

## Adding real listings for now
Until posting is wired, add rows in **Table Editor → listings** with
`status = live`, `purpose = rent|sale`, `market = AE`, and `area` matching a
community name (for counts and autocomplete).
