# TravelPlanner

A Flutter travel-planning app UI. Every screen is built and navigable end
to end. Most modules still run on local/dummy data — it's a UI/UX
prototype for a Penang, Malaysia trip ("Penang Adventure": Komtar →
Gurney Drive → Queensbay Mall). The **Authentication**, **Budget**, and
**Group Travel** modules are the exception: they're wired to a real,
shared Supabase backend (see below).

## Getting Started

```bash
flutter pub get
flutter run -d chrome   # or -d windows, -d <device-id>
```

`main.dart` boots into `SplashScreen`, which auto-advances into the
onboarding/auth flow described below.

## Tech stack

- Flutter / Material 3, single package, no state-management library —
  screens use local `State`, mostly still with dummy `const` data lists.
- Auth, Budget, and Group Travel are the exception (Supabase-backed —
  see below); everywhere else, "submit"/"save" either navigates forward
  or shows a `showComingSoon()` snackbar (see `lib/widgets/coming_soon.dart`).
- Shared design system in `lib/theme/app_theme.dart` (`AppColors`,
  gradients) and `lib/widgets/` (see below).

## Backend (Auth + Budget + Group modules)

`lib/services/`, `lib/models/`, and `lib/utils/` hold a Supabase-backed
data layer shared by three modules, all reading/writing it live instead
of local mock data:

- **Authentication** — real sign up/in/out, password reset via emailed
  link, 6-digit sign-up email verification, friendly error messages,
  client-side validation.
- **Budget** — total budget, category planning, expense CRUD,
  per-member balances.
- **Group Travel** — live member roster, realtime chat, realtime
  polls/voting, invite codes, join requests.

**Setup**

1. Create a Supabase project, then run `supabase/schema.sql` against it
   (SQL Editor, or `supabase db push`) — see `SUPABASE_SETUP.md` for a
   full walkthrough (creating the project, Auth provider config, the
   redirect URL needed for password-reset links). If you already ran an
   earlier version of this schema, run
   `supabase/migrations/0001_add_auth_profile_fields.sql` instead to
   bring it up to date.
2. In Authentication → Providers → Email, make sure **"Confirm email"
   is ON** — `VerifyEmailScreen` submits the real 6-digit code from
   Supabase's confirmation email (Email Templates → Confirm signup must
   still contain `{{ .Token }}`).
3. Authentication → URL Configuration → add `http://localhost:8766/**`
   to both **Site URL** and **Redirect URLs**, and always run with
   `--web-port=8766` — this lets a password-reset email link land back
   in the running app and auto-open Reset Password.
4. Copy `.env.example` to `.env` and fill in your project's URL and
   anon/publishable key (Project Settings → API). `.env` is gitignored.
5. `flutter pub get`, then `flutter run -d chrome --web-port=8766` —
   `main.dart` calls `SupabaseConfig.load()` before `runApp`.

**No trip selection exists anywhere else in the app yet** (Trip Planner
module), so `TripService.ensureDemoTrip()` auto-creates/reuses one
"Penang Adventure" trip per signed-in user as a stand-in — every
Budget/Group screen resolves it internally, so no navigation call
sites outside `screens/budget/` and `screens/group/` needed to change.
Swap this out once real trip creation/selection lands.

Joining a trip is now a real request/approve flow, not instant: enter
a code on **Join a Trip** and it files a pending request; the trip's
organizer approves/rejects it from **Invite Member**'s "Join Requests"
list.

| File | Covers |
|---|---|
| `services/auth_service.dart` | Wraps every Supabase Auth call (sign up/in/out, password reset, OTP verify/resend) |
| `services/auth_error_messages.dart` | Maps raw Supabase auth errors to user-facing messages |
| `utils/validators.dart` | Client-side email/password/name field validation |
| `services/trip_service.dart` | Resolves/creates the demo trip (see above) |
| `services/budget_service.dart` | Total budget, category planning, expense CRUD, per-member balances |
| `services/group_service.dart` | Member roster, invite codes, join requests |
| `services/chat_service.dart` | Realtime group chat |
| `services/poll_service.dart` | Polls, options, live vote tallies |

The `profiles` table is shared by all three modules: `display_name` /
`avatar_color` are read by Budget/Group (member names, chat senders,
avatars), `full_name` / `email` / `avatar_url` are owned by
Authentication — one sign-up trigger (in `schema.sql`) populates both
sets of columns so neither module clobbers the other's data.

## Shared widgets (`lib/widgets/`)

| Widget | Purpose |
|---|---|
| `GradientButton` | Primary pill CTA button used across the app |
| `SectionHeader` | Title + optional "See all" action for list sections |
| `DetailHeader` | Back button + title/subtitle for pushed (interior) screens |
| `SimpleCard` | Shadowed rounded container used for grouped content |
| `ListTileCard` | Icon + title/subtitle + trailing tappable row (menus, settings, saved items) |
| `showComingSoon()` | Snackbar helper for UI-only actions with no real backend |

## Navigation structure

```
SplashScreen
  → WelcomeScreen (onboarding carousel: Skip / Next / Get Started)
      → AuthScreen (Sign In / Sign Up toggle)
          Sign In            → HomeScreen (5-tab shell)
          Sign Up            → VerifyEmailScreen → HomeScreen
          Forgot password?   → ForgotPasswordScreen
                                  → ResetPasswordScreen → back to AuthScreen

HomeScreen (bottom nav, 5 tabs)
  ├─ Home        (dashboard)
  ├─ Trips       (TripsTab)
  ├─ Explore     (ExploreTab)
  ├─ Community   (CommunityTab)
  └─ Profile     (ProfileTab)
```

Screens reached by pushing (not part of the bottom nav) are nested
under the tab/section that links to them below.

### Auth Module — Supabase-backed
`splash_screen.dart` · `welcome_screen.dart` · `auth_screen.dart` ·
`forgot_password_screen.dart` · `reset_password_screen.dart` ·
`verify_email_screen.dart`

Splash (skips straight to Home if a session is already active) →
onboarding carousel → combined sign in/sign up screen → forgot-password
(emailed reset link) / reset-password → 6-digit email verification (a
real Supabase OTP). Live data — see "Backend" above.

### Home tab
`home_screen.dart` (dashboard body) · `search_destination_screen.dart` ·
`notifications_screen.dart`

- **Dashboard**: greeting header (→ Notifications), search bar (→
  Search Destination), upcoming-trip hero card (→ Trip Details),
  quick actions (New Trip → Create Trip, Flights/Hotels → coming
  soon, Budget → Budget Planner), weather card (→ Weather Forecast),
  trip itinerary carousel, explore-destinations carousel, recent
  activity list.
- **Search Destination**: recent searches + live filter over the
  Explore place list → Place Details.
- **Notifications**: grouped alerts (today / earlier).

### Trips tab — Trip Planner Module
`trip/trips_tab.dart` · `trip/create_trip_screen.dart` ·
`trip/ai_planner_screen.dart` · `trip/trip_details_screen.dart` ·
`trip/edit_schedule_screen.dart` · `trip/daily_timeline_screen.dart` ·
`trip/map_view_screen.dart`

- **Trips tab**: upcoming + past trips list. "+" → Create Trip.
- **Create Trip**: destination/dates/travelers/budget/interests form →
  **AI Planner** (animated "generating itinerary" steps) →
- **Trip Details**: hub screen — stats row, **Trip Tools** grid
  (Daily Timeline, Edit Schedule, Map View, Weather, Transport,
  Budget, Utilities, Group), and the itinerary stop list.
- **Edit Schedule**: drag-to-reorder stop list.
- **Daily Timeline**: day-by-day vertical timeline of activities.
- **Map View**: stylized pin map (no map SDK) + route legs between
  stops.

### Weather Module
`weather/weather_forecast_screen.dart` · `weather/weather_alert_screen.dart`

Current conditions, hourly strip, 5-day outlook; a bell icon opens
active/past **Weather Alerts**. Reached from the home dashboard
weather card and the Trip Details tools grid.

### Transport Module
`transport/transport_routes_screen.dart` ·
`transport/route_details_screen.dart` ·
`transport/fare_calculator_screen.dart`

Route list (bus/e-hailing/ferry) between trip stops → step-by-step
**Route Details** → **Fare Calculator** (distance slider, per-mode
fare estimate). Reached from Trip Details tools grid.

### Explore tab — Explore Module
`explore/explore_tab.dart` · `explore/categories_screen.dart` ·
`explore/place_details_screen.dart` · `explore/nearby_places_screen.dart`

- **Explore tab**: category filter chips, nearby-places strip,
  popular-destinations list (all Penang places, defined once in
  `explore_tab.dart` and reused across Search, Saved, and Nearby).
- **Categories**: browse-by-interest grid → filtered place list.
- **Place Details**: hero, tags, description, hours, rating summary
  → Reviews (Community module) / Add Review / Directions.
- **Nearby Places**: full list sorted by distance.

### Community tab — Community Module
`community/community_tab.dart` · `community/review_details_screen.dart` ·
`community/add_review_screen.dart` · `community/comments_screen.dart`

- **Community tab**: travel-story feed (like / comment / share).
- **Review Details**: rating breakdown + review list for a place →
  Add Review.
- **Add Review**: star rating + text submission.
- **Comments**: comment thread with local "post" support.

### Saved Module
`saved/saved_places_screen.dart` · `saved/saved_trips_screen.dart`

Bookmarked places (grid, un-save supported) and bookmarked/draft
itineraries. Reached from the Profile menu.

### Budget Module — Supabase-backed
`budget/budget_planner_screen.dart` · `budget/expense_tracker_screen.dart` ·
`budget/expense_split_screen.dart`

Total-vs-spent overview with category breakdown → **Expense
Tracker** (add expenses via bottom sheet) / **Expense Split**
(per-traveler balances, editable by the organizer). Reached from the
home dashboard Budget quick action and the Trip Details tools grid.
Live data — see "Backend" above.

### Utilities Module
`utilities/utilities_home_screen.dart` · `utilities/packing_list_screen.dart` ·
`utilities/currency_converter_screen.dart` · `utilities/translator_screen.dart` ·
`utilities/emergency_contacts_screen.dart`

A hub screen (linked from Trip Details tools grid) listing:
auto-generated **Packing List** (checkboxes), **Currency Converter**
(MYR ↔ other currencies, dummy fixed rates), **Translator**
(English ↔ Bahasa Malaysia phrasebook), **Emergency Contacts** (local
numbers for Penang).

### Group Travel Module — Supabase-backed
`group/group_dashboard_screen.dart` · `group/group_chat_screen.dart` ·
`group/voting_screen.dart` · `group/poll_form_screen.dart` ·
`group/invite_member_screen.dart` · `group/join_trip_screen.dart`

A hub screen (linked from Trip Details tools grid) showing the live
member roster, with links to: **Group Chat** (realtime), **Voting**
(create/edit/delete polls, live tallies via **Poll Form**), and
**Invite Member** (generate a code, approve/reject join requests).
**Join a Trip** (reached from the home dashboard) is the requester
side. Live data — see "Backend" above.

### Profile tab — Profile Module
`profile/profile_tab.dart` · `profile/travel_history_screen.dart` ·
`profile/achievements_screen.dart` · `profile/settings_screen.dart`

- **Profile tab**: identity header + stats, menu into Travel History,
  Achievements, Saved Places, Saved Trips, Settings, Sign Out (→
  back to `WelcomeScreen`).
- **Travel History**: timeline of past trips.
- **Achievements**: earned/locked badge grid.
- **Settings**: notification/appearance toggles, account, support,
  sign out.

## Project structure

```
lib/
  main.dart                 # Supabase init, MaterialApp, home: SplashScreen
  theme/app_theme.dart       # AppColors, gradients, ThemeData
  widgets/                   # shared components (see table above)
  models/                    # Expense, BudgetCategoryData, TripBalance,
                              # GroupMember, GroupMessage, Poll, JoinRequest
  services/                  # SupabaseConfig + Auth/Budget/Group backend (see above)
  utils/validators.dart      # Auth form validation
  screens/
    splash_screen.dart
    welcome_screen.dart
    auth_screen.dart
    forgot_password_screen.dart
    reset_password_screen.dart
    verify_email_screen.dart
    home_screen.dart          # 5-tab shell + dashboard body
    search_destination_screen.dart
    notifications_screen.dart
    trip/        edit_schedule_screen.dart, ai_planner_screen.dart, ...
    weather/      weather_forecast_screen.dart, weather_alert_screen.dart
    transport/    transport_routes_screen.dart, route_details_screen.dart, ...
    explore/      explore_tab.dart, place_details_screen.dart, ...
    community/    community_tab.dart, review_details_screen.dart, ...
    saved/        saved_places_screen.dart, saved_trips_screen.dart
    budget/       budget_planner_screen.dart, expense_tracker_screen.dart, ...
    utilities/    utilities_home_screen.dart, packing_list_screen.dart, ...
    group/        group_dashboard_screen.dart, group_chat_screen.dart, ...
    profile/      profile_tab.dart, settings_screen.dart, ...
```
