# VELUSH Final E-commerce

Complete multi-page customer storefront + Supabase backend + secure admin area.

## Preview architecture
- GitHub Pages: static client preview only.
- Supabase: database, Auth, Storage, Edge Functions.
- Browser localStorage: cart only. Orders are stored server-side.

## Setup
1. Copy `js/config.example.js` to `js/config.js` and add only the Supabase project URL + publishable/anon key.
2. Run `supabase/schema.sql` in Supabase SQL editor.
3. Create a Supabase Auth user for the admin. Then add its UUID to `public.profiles` with role `admin`.
4. Deploy `supabase/functions/create-order` and set `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` as Edge Function secrets.
5. Deploy `supabase/functions/payment-init`. Set `BKASH_ENABLED`, `NAGAD_ENABLED`, or `ONLINE_ENABLED` only after the matching provider implementation and merchant credentials are configured.
6. From Admin → Products, use `Sync 7 seed products`, then upload the supplied product images into each product.
7. Configure confirmed contact information and store settings from Admin → Website Settings.

## Initial products
The database seed includes exactly 7 products: 3 Polos + 4 T-Shirts, all M/L, with the supplied prices and initial stock 20.

## Security
Never commit service-role keys, payment secrets, passwords, or private tokens. Only browser-safe Supabase config belongs in `js/config.js`.

## Payment state
COD is fully usable. bKash/Nagad/online payment are intentionally not reported as successful unless the corresponding provider integration is configured.

## Deployment
Use GitHub Pages for review/staging only. For the official `.com` launch, deploy the same static frontend to Vercel, Netlify, Cloudflare Pages, or similar and keep Supabase as the backend.

## GitHub Pages client preview
1. Push the repository to GitHub with `main` as the preview branch.
2. In repository Settings → Pages, choose **GitHub Actions**.
3. The included `.github/workflows/pages.yml` deploys the repository as a static client preview.
4. Before enabling real ordering on the preview, set the safe Supabase URL/key in `js/config.js` and deploy the backend functions. Never commit server secrets.
