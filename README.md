# YourTurn

YourTurn is a collaborative travel album where one person receives the daily turn and chooses the official photo of the day. Everyone can still add regular photos. The project uses a single-file frontend, Supabase for authentication/database/storage/realtime, and Vercel for the public web app.

## Live app

- Production: https://yourturn-virid.vercel.app
- Current stable frontend: `index.html` / `versions/stable-v11.html`
- Latest development prototype: `versions/development-v10-shared-caption.html`

## Current status

The stable production version includes:

- anonymous Supabase authentication
- creating and joining trips
- multiple-trip dashboard with automatic photo previews
- daily turn assignment and pass mechanic
- private photo storage with signed URLs
- likes, realtime updates and trip deletion by the creator
- push-notification backend for the current turn holder

The development v10 prototype additionally contains the redesigned daily-cover view and one shared description per main photo. Its database schema is included, but that frontend is not the current production version because the previous nested loader rollout was reverted.

## Repository layout

- `index.html` — current stable app
- `versions/` — preserved frontend snapshots and experiments
- `supabase/migrations/current_schema.sql` — reproducible current database schema snapshot
- `supabase/functions/` — production Edge Functions
- `docs/ARCHITECTURE.md` — system overview
- `docs/DEPLOYMENT.md` — deployment notes
- `docs/CHANGELOG.md` — version history

## Local use

The frontend is a self-contained HTML file. Serve the repository with any static server, for example:

```bash
python3 -m http.server 8080
```

Then open `http://localhost:8080`.

## Security

The Supabase publishable key used by the browser is intentionally public. Never commit the service-role key, VAPID private key or cron secret. Real secret values are not included in this repository.

## License

No license has been selected yet.
