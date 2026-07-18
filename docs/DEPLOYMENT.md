# Deployment

## Supabase

1. Create a Supabase project.
2. Run `supabase/migrations/current_schema.sql` in the SQL editor or through the Supabase CLI.
3. Create the private `photos` bucket if the migration did not create it automatically.
4. Deploy the Edge Functions in `supabase/functions/`.
5. Configure the following Edge Function secrets:
   - `VAPID_PUBLIC_KEY`
   - `VAPID_PRIVATE_KEY`
   - `VAPID_SUBJECT`
   - `CRON_SECRET`
6. Store the same cron secret in `public.private_config` under the key `cron_secret`.

## Frontend

The root `index.html` is the stable snapshot. Update its Supabase URL and publishable key when deploying to a different project.

## Vercel

Deploy the repository as a static project. `vercel.json` disables caching and adds basic security headers.

## Production references

- Supabase project reference: `hvjvcdhknqajoyjudweg`
- Vercel project: `yourturn`
- Production alias: `yourturn-virid.vercel.app`

Do not commit service-role credentials or private push keys.
