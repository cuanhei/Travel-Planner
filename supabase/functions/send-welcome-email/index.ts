// Sends a "You're signed up for TravelPlanner" welcome email the moment a
// new account is created. Triggered by a Supabase Database Webhook on
// INSERT into public.profiles (see SUPABASE_SETUP.md's "Welcome email on
// sign-up" section for how to wire that webhook up) — profiles rows are
// created by the `handle_new_user` trigger (see supabase/schema.sql) the
// instant `AuthService.signUp` succeeds, so this fires right at sign-up,
// separately from (and in addition to) the sign-up confirmation code
// Supabase's own "Confirm signup" email template sends.
//
// Deploy with:
//   supabase functions deploy send-welcome-email
//
// Requires one function secret (Project Settings > Edge Functions, or
// `supabase secrets set`):
//   RESEND_API_KEY — from resend.com (free tier is enough)
//
// Unlike send-login-alert, no SUPABASE_SERVICE_ROLE_KEY lookup is needed —
// the profiles row that triggered this already carries its own email.
//
// Deliberately swallows its own errors and always responds 200 — this is a
// best-effort notification, not part of the sign-up critical path, and a
// non-2xx response would make Supabase's Database Webhooks retry (and
// potentially resend the same email multiple times).

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';

interface ProfileRow {
  email: string | null;
  display_name: string | null;
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload?.record as ProfileRow | undefined;
    if (!record?.email) {
      return new Response('no email', { status: 200 });
    }

    const name = record.display_name?.trim() || 'there';

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'TravelPlanner <onboarding@resend.dev>',
        to: record.email,
        subject: "You're signed up for TravelPlanner!",
        html: `
          <h2>Welcome to TravelPlanner, ${name}!</h2>
          <p>Your account has been created — you're all set to start
          planning trips, exploring destinations, and connecting with
          fellow travelers.</p>
          <p>If you didn't sign up for this, you can safely ignore this
          email.</p>
        `,
      }),
    });

    if (!res.ok) {
      console.error(
        'send-welcome-email: Resend send failed',
        await res.text(),
      );
    }
    return new Response('ok', { status: 200 });
  } catch (e) {
    console.error('send-welcome-email: unexpected error', e);
    return new Response('error', { status: 200 });
  }
});
