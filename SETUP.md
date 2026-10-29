# San Rafael 2026

Family-based weekend expense splitter.

## Current version

Open `index.html` in a browser. Add families, expenses, and split them equally or by custom amounts. Balances and settlement recommendations are computed automatically. Amounts are stored in integer cents to avoid floating-point rounding errors.

**Important:** This version uses browser localStorage, not a shared database. Data does not sync between devices. Use Export JSON to back up your data. Do not treat GitHub Pages as a secure expense database.

## Publish with GitHub Pages

If your GitHub plan permits Pages for this repository, open Settings → Pages → Deploy from a branch → main → / (root). For free personal Pages hosting, make the repository public first. The URL will be https://unmaskedspirit.github.io/san-rafael-2026/ after deployment.

## Next milestone: shared collaboration

Connect a backend (e.g. Supabase) with authenticated trip membership and row-level security. Store families and expenses in database tables; restrict read/write to authorized trip members. Do not put Supabase service-role keys or shared secrets in this public frontend. A simple access code must be verified server-side, not only in JavaScript.
