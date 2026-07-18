-- Optional scheduled turn creation and Web Push delivery.
-- Configure CRON_SECRET both as an Edge Function secret and in private_config.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

create or replace function public.trigger_turn_pings()
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_secret text;
  v_id bigint;
begin
  select value into v_secret from public.private_config where key = 'cron_secret';
  select net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-turn-pings',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret', v_secret),
    body := '{}'::jsonb
  ) into v_id;
  return v_id;
end;
$$;

revoke all on function public.trigger_turn_pings() from public, anon, authenticated;
grant execute on function public.trigger_turn_pings() to service_role;

-- Replace existing jobs when applying manually.
select cron.unschedule(jobid)
from cron.job
where jobname in ('yourturn-daily-turns', 'yourturn-turn-pings');

select cron.schedule(
  'yourturn-daily-turns',
  '0 6 * * *',
  'select public.ensure_daily_turns();'
);

select cron.schedule(
  'yourturn-turn-pings',
  '5 6 * * *',
  'select public.trigger_turn_pings();'
);
