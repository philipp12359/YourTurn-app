# Architecture

## Frontend

YourTurn is currently delivered as a self-contained HTML/CSS/JavaScript application. It uses `@supabase/supabase-js` in the browser and stores the active trip slug in local storage.

## Authentication

Users sign in anonymously through Supabase Auth. A membership row connects the anonymous user ID to a trip and display name. Losing the anonymous browser session can therefore make old memberships inaccessible to that browser.

## Database

Core tables:

- `trips`
- `members`
- `photos`
- `turns`
- `turn_passes`
- `likes`
- `push_subscriptions`
- `main_photo_captions`

Row Level Security restricts data to trip members. Security-definer RPC functions handle trip creation/joining, turn completion, passing, dashboard listings and caption clearing.

## Storage

The private `photos` bucket stores objects beneath the trip UUID folder. Trip members can read and upload. Users can delete their own objects. The creator-only `delete-trip` Edge Function uses the service role to remove all objects before deleting the trip record.

## Turn mechanic

Each trip has one turn per date. Completing a turn marks one uploaded photo as the daily anchor and schedules the next member. Passing reassigns the same pending turn to another eligible member and records the hand-off in `turn_passes`.

## Notifications

`pg_cron` runs `ensure_daily_turns()` every morning and calls `trigger_turn_pings()` shortly afterward. The `send-turn-pings` Edge Function sends Web Push notifications to the current turn holder.

## Hosting

The public domain is hosted on Vercel. The stable production loader currently obtains the app from the `yourturn-app` Supabase Edge Function.
