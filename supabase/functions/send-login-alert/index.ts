// Sends "New sign-in to your account" emails. Triggered by a Supabase
// Database Webhook on INSERT into public.login_activity (see
// SUPABASE_SETUP.md's "Email alert on new sign-in" section for how to wire
// that webhook up) — so this fires once per real sign-in, from the same
// `signedIn` event that already writes the login_activity row (see the
// `onAuthStateChange` listener in lib/main.dart).
//
// Deploy with:
//   supabase functions deploy send-login-alert
//
// Requires two function secrets (Project Settings > Edge Functions, or
// `supabase secrets set`):
//   RESEND_API_KEY            — from resend.com (free tier is enough)
//   SUPABASE_SERVICE_ROLE_KEY — from Project Settings > API (needed to look
//                                up the signed-in user's email by id; the
//                                anon key can't do this)
//
// Deliberately swallows its own errors and always responds 200 — this is a
// best-effort notification, not part of the sign-in critical path, and a
// non-2xx response would make Supabase's Database Webhooks retry (and
// potentially resend the same alert multiple times).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

interface LoginActivityRow {
  user_id: string;
  signed_in_at: string;
  device_info: string | null;
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload?.record as LoginActivityRow | undefined;
    if (!record?.user_id) {
      return new Response('no record', { status: 200 });
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data, error } = await admin.auth.admin.getUserById(
      record.user_id,
    );
    const email = data?.user?.email;
    if (error || !email) {
      console.error('send-login-alert: user lookup failed', error);
      return new Response('user lookup failed', { status: 200 });
    }

    const when = new Date(record.signed_in_at).toUTCString();
    const device = record.device_info ?? 'an unknown device';

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'TravelPlanner <onboarding@resend.dev>',
        to: email,
        subject: 'New sign-in to your TravelPlanner account',
        html: `
          <h2>New sign-in detected</h2>
          <p>Your TravelPlanner account was just signed into.</p>
          <ul>
            <li><strong>When:</strong> ${when}</li>
            <li><strong>Device:</strong> ${device}</li>
          </ul>
          <p>If this wasn't you, change your password immediately from
          Settings &gt; Privacy &amp; Security &gt; Change Password.</p>
        `,
      }),
    });

    if (!res.ok) {
      console.error('send-login-alert: Resend send failed', await res.text());
    }
    return new Response('ok', { status: 200 });
  } catch (e) {
    console.error('send-login-alert: unexpected error', e);
    return new Response('error', { status: 200 });
  }
});
