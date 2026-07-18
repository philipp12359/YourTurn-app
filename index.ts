// Schickt genau der Person einen Web-Push, die heute dran ist.
// Aufruf: per pg_cron (pg_net) mit Header x-cron-secret.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'https://esm.sh/web-push@3.6.7';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? '';

Deno.serve(async (req) => {
  if (CRON_SECRET && req.headers.get('x-cron-secret') !== CRON_SECRET) {
    return new Response('forbidden', { status: 403 });
  }

  const pub = Deno.env.get('VAPID_PUBLIC_KEY');
  const priv = Deno.env.get('VAPID_PRIVATE_KEY');
  const subject = Deno.env.get('VAPID_SUBJECT') ?? 'mailto:hello@yourturn.app';
  if (!pub || !priv) {
    return new Response(JSON.stringify({ error: 'VAPID keys missing' }), { status: 500 });
  }
  webpush.setVapidDetails(subject, pub, priv);

  const sb = createClient(url, serviceKey);
  const today = new Date().toISOString().slice(0, 10);

  const { data: turns, error } = await sb
    .from('turns')
    .select('id, trip_id, member_id, trips(name), members(display_name)')
    .eq('turn_date', today)
    .eq('status', 'pending')
    .is('notified_at', null);

  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  let sent = 0, failed = 0;

  for (const turn of turns ?? []) {
    const { data: subs } = await sb
      .from('push_subscriptions')
      .select('*')
      .eq('member_id', turn.member_id);

    if (!subs?.length) continue;

    const tripName = (turn as any).trips?.name ?? 'your trip';
    const payload = JSON.stringify({
      title: "You're up.",
      body: `${tripName} — take today's photo whenever it feels right.`,
      tag: 'turn-' + turn.id,
      url: '/',
    });

    for (const s of subs) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload,
        );
        sent++;
      } catch (e) {
        failed++;
        const status = (e as any)?.statusCode;
        if (status === 404 || status === 410) {
          await sb.from('push_subscriptions').delete().eq('id', s.id);
        } else {
          await sb.from('push_subscriptions')
            .update({ last_error: String((e as any)?.message ?? e), failed_at: new Date().toISOString() })
            .eq('id', s.id);
        }
      }
    }

    await sb.from('turns').update({ notified_at: new Date().toISOString() }).eq('id', turn.id);
  }

  return new Response(JSON.stringify({ turns: turns?.length ?? 0, sent, failed }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
