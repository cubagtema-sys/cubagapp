# SEC-04 — switch the Supabase `uploads` bucket to private (owner action)

The backend and app changes on branch `release/p0-hardening` already request
short-lived signed URLs for receipts and compliance/member documents, and fall
back to the old public URL while the bucket is still public. So:

1. **Deploy the backend** from this branch first (staging, then production).
2. **Ship the new app build** (or confirm the deployed web portal is rebuilt).
3. Supabase Dashboard → Storage → `uploads` → Edit bucket → turn **Public** off.
4. Gallery images and profile photos must stay public. Before step 3:
   create a new **public** bucket (e.g. `public-assets`) and set
   `SUPABASE_PUBLIC_BUCKET=public-assets` on the server. New gallery uploads and
   profile photos then go there. Existing gallery/avatar objects in `uploads`
   must be copied to the new bucket and their DB URLs updated
   (`events_gallery`/`gallery` image URLs, `members.profile_photo`) — or they
   will stop loading after step 3.
5. Verify: open an old receipt URL in a private browser window → must fail;
   open the same receipt from the app → must work.

Rollback: turn **Public** back on (instant).
