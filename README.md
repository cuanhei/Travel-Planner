# TravelPlanner

A Flutter travel-planning app UI. Every screen is built and navigable end
to end, but all data is local/dummy — there is no backend, API, or
persistence. It's a UI/UX prototype for a Penang, Malaysia trip
("Penang Adventure": Komtar → Gurney Drive → Queensbay Mall).

## Getting Started

```bash
flutter pub get
flutter run -d chrome   # or -d windows, -d <device-id>
```

`main.dart` boots into `SplashScreen`, which auto-advances into the
onboarding/auth flow described below.

## Tech stack

- Flutter / Material 3, single package, no state-management library —
  screens use local `State` and dummy `const` data lists.
- No `http`, no backend, no persistence. Every "submit", "save", or
  "sign in" action either navigates forward or shows a
  `showComingSoon()` snackbar (see `lib/widgets/coming_soon.dart`).
- Shared design system in `lib/theme/app_theme.dart` (`AppColors`,
  gradients) and `lib/widgets/` (see below).

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

### Auth Module
`splash_screen.dart` · `welcome_screen.dart` · `auth_screen.dart` ·
`forgot_password_screen.dart` · `reset_password_screen.dart` ·
`verify_email_screen.dart`

Splash → onboarding carousel → combined sign in/sign up screen →
forgot-password / reset-password flow → email verification. Signing
in (any valid-looking input) or completing verification lands on the
home dashboard.

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

### Budget Module
`budget/budget_planner_screen.dart` · `budget/expense_tracker_screen.dart` ·
`budget/expense_split_screen.dart`

Total-vs-spent overview with category breakdown → **Expense
Tracker** (add expenses via bottom sheet) / **Expense Split**
(per-traveler balances). Reached from the home dashboard Budget quick
action and the Trip Details tools grid.

### Utilities Module
`utilities/utilities_home_screen.dart` · `utilities/packing_list_screen.dart` ·
`utilities/currency_converter_screen.dart` · `utilities/translator_screen.dart` ·
`utilities/emergency_contacts_screen.dart`

A hub screen (linked from Trip Details tools grid) listing:
auto-generated **Packing List** (checkboxes), **Currency Converter**
(MYR ↔ other currencies, dummy fixed rates), **Translator**
(English ↔ Bahasa Malaysia phrasebook), **Emergency Contacts** (local
numbers for Penang).

### Group Travel Module
`group/group_dashboard_screen.dart` · `group/shared_itinerary_screen.dart` ·
`group/group_chat_screen.dart` · `group/voting_screen.dart`

A hub screen (linked from Trip Details tools grid) showing trip
members, with links to: **Shared Itinerary** (who edited what),
**Group Chat** (local send), **Voting** (tap-to-vote polls with live
results).

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
  main.dart                 # MaterialApp, home: SplashScreen
  theme/app_theme.dart       # AppColors, gradients, ThemeData
  widgets/                   # shared components (see table above)
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
