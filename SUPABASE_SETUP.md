# Supabase Setup

The Authentication module (Splash, Onboarding, Sign In/Up, Forgot/Reset
Password, Email Verification) is wired up to Supabase Auth. To run the app
you need a Supabase project and its URL/anon key — everyone on the team
should point at the **same** project so data lands in one shared database.

## 1. Create the project

1. Go to [supabase.com](https://supabase.com) and sign in (GitHub login is
   easiest).
2. **New project** →
   - **Organization** — create one if needed (name it after the team/course).
   - **Name** — e.g. `travelplanner`.
   - **Database password** — generate one and save it (only needed for direct
     DB access later, not for the app itself).
   - **Region** — closest to the team.
   - **Plan** — Free tier is enough.
3. Create, then wait ~1–2 minutes while it provisions.

## 2. Get the URL + anon key

**Project Settings** (gear icon) → **API** (some dashboard versions label
this **Data API**):

- **Project URL** → this is `SUPABASE_URL`
- Under **Project API keys**, the **`anon` `public`** key (sometimes labeled
  **"publishable key"** on newer dashboards) → this is `SUPABASE_ANON_KEY`

Never use the **`service_role`** key here — it bypasses all security and
must stay server-side only.

Share these two values with the team (e.g. in your group chat or a shared
password manager) — don't commit them to the repo.

## 3. Configure Auth

In the dashboard, **Authentication**:

- **Providers → Email** → make sure **"Confirm email"** is **ON**.
- **Email Templates → Confirm signup** → check it still contains
  `{{ .Token }}` (the default template does) — that's the 6-digit code the
  Verify Email screen submits.
- **Email Templates → Reset Password** → the default template only has a
  link, not a code — replace its body with something like:
  ```html
  <h2>Reset Password</h2>
  <p>Enter this code in the app to reset your password:</p>
  <h1>{{ .Token }}</h1>
  <p>If you didn't request this, you can safely ignore this email.</p>
  ```
  Deliberately code-based rather than link-based: a single-click email link
  can get silently consumed by mail-provider link-prescanning (the same
  issue that affects sign-up confirmation links) before the user ever opens
  it, and it also depends on the click landing in the same browser profile
  that requested it. A manually-typed code sidesteps both — so leave
  `{{ .ConfirmationURL }}` out of this template entirely.
- **Email Templates → Magic Link** → same deal, needed for the email-based
  two-factor code (Settings → Privacy & Security → Two-Factor
  Authentication). Replace its body with something like:
  ```html
  <h2>Sign-In Code</h2>
  <p>Enter this code to finish signing in:</p>
  <h1>{{ .Token }}</h1>
  <p>If you didn't try to sign in, you can safely ignore this email.</p>
  ```
  Without this, the email that goes out only contains a clickable link and
  the code screen has nothing for the user to type in.
- If sign-up ever fails with a generic `email_address_invalid` error for an
  address that's clearly valid (e.g. a Gmail address), check **Providers →
  Email → Allowed email domains** (or a similarly named restriction under
  Auth settings) — an accidentally-narrow allow-list produces this exact
  misleading error instead of a clearer "domain not allowed" one.

## 4. Create the `profiles` table

Auth only stores login credentials — actual user data (name, etc.) lives in
a `public.profiles` table that's kept in sync automatically. Open the
**SQL Editor** in the dashboard, paste in the contents of
[`supabase/migrations/0001_create_profiles.sql`](supabase/migrations/0001_create_profiles.sql),
and run it once against the shared project. This creates the table, locks
it down with Row Level Security (each user can only read/edit their own
row), and adds a trigger that inserts a row here the moment someone signs
up.

## 4b. Create the support ticket tables

The Help Center's "Contact Support" screen and ticket thread (Profile →
Help Center) are backed by two tables — no real email is sent. Open the
**SQL Editor** and run
[`supabase/migrations/0002_create_support_tickets.sql`](supabase/migrations/0002_create_support_tickets.sql)
once. This creates `support_tickets` and `support_messages`, locked down so
each user only sees their own.

**Replying as support**: open **Table Editor → support_messages**, insert a
row with `ticket_id` set to the ticket you're replying to (copy it from the
matching row in `support_tickets`), `sender` set to `support`, and `body`
set to your reply. The customer sees it next time they open that ticket in
the app. (Only the dashboard can do this — the app's own RLS policy only
lets a signed-in user insert `sender = 'customer'` rows on their own
tickets.)

## 5. Run the app

Always use the same fixed port (`8766`) so it matches the redirect URL
configured above:

```
flutter run -d chrome --web-port=8766 \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Without these `--dart-define` values the app still runs, but
`SupabaseConfig.isConfigured` is `false` and auth calls are skipped — you'll
just see the UI flow with no real backend behind it.

## How it's wired up

- `lib/services/supabase_config.dart` — reads the two values above from
  `--dart-define`.
- `lib/services/auth_service.dart` — wraps every Supabase Auth call used by
  the module (`signUp`, `signIn`, `signOut`, `sendPasswordResetEmail`,
  `updatePassword`, `verifySignupCode`, `resendSignupCode`).
- `lib/main.dart` — initializes Supabase on startup. Password reset is
  entirely in-app (email → 6-digit code → Reset Password screen), so
  there's no redirect/URL handling to worry about.
- `lib/utils/validators.dart` — client-side field validation (email format,
  password strength, confirm-password match) shown inline before a request
  is even sent.
- `lib/services/auth_error_messages.dart` — maps Supabase's raw error codes
  (wrong password, duplicate email, expired code, rate limiting, etc.) to
  short, user-facing messages shown in a snackbar.
- `supabase/migrations/0001_create_profiles.sql` — the `profiles` table
  schema (see step 4 above).
