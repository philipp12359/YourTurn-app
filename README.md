# App assets

The production `yourturn-app` Edge Function currently reads the stable wrapper from the `public.app_assets` row with key `yourturn_wrapper_v9`.

The database row itself is not included because it is a generated delivery wrapper. The actual stable source is preserved at the repository root as `index.html` and in `versions/stable-v11.html`.

For a cleaner future deployment, serve the root HTML directly from Vercel or package it as a normal Edge Function asset instead of nesting generated scripts.
