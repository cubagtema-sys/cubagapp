# CUBAG — Implementation Roadmap

**Principle:** fix what is exploitable or blocks submission first, in small reviewable batches, without rebuilding working features. Each batch ends with its own tests and a deploy you can roll back.

**Estimates** assume one experienced Flutter/Python developer and are indicative only. They exclude store review time and legal review.

```
Week:        1        2        3        4        5        6        7        8
Phase 0  ■ (owner checks, parallel)
Phase 1  ■■■■■■■■■■
Phase 2           ■■■■■■■■■■
Phase 3      ■■■■■■■■■■■■■■■ (content/legal, parallel)
Phase 4                    ■■■■■■■■
Phase 5                             ■■■■■■■■
Phase 6                             ■■■■■■■■■■■■■■■■■■■■ (ongoing)
Submit                              ▲ internal/TestFlight   ▲ store review
```

---

## Phase 0 — Owner verifications (days 1–2, no code)

**Why first:** several fixes depend on facts only the owner can check (Supabase settings, secret rotation, deployed Worker, product decisions).

- Supabase: RLS / grants / bucket visibility (SEC-10, SEC-04).
- Secrets: confirm rotation; remove the token from `.git/config` (SEC-09).
- Cloudflare: delete the WhitsunPay proxy Worker if deployed (SEC-08).
- Decisions: Android application ID, iPad in v1, messaging scope, CTI online-course payments on iOS.
- Accounts: organisation developer accounts (Apple, Google) — the D-U-N-S lookup can take days, so start now.

**Exit criteria:** every Phase 0 row in the checklist is `[x]` or has an owner and a date.

## Phase 1 — Critical backend security (≈ 1.5 weeks)

Small, independent PRs in this order (highest impact, lowest effort first):

1. **Authorisation patches (1 day):** SEC-01, SEC-02 (complaints), SEC-06 (GDPR + compliance settings), SEC-19 (compliance webhook fail-closed). One shared helper, `require_permission(key)`, reusing `sub_admin_required`.
2. **Public endpoint lockdown (½ day):** SEC-03 certificate endpoint; SEC-05 remove/harden `news/proxy-image`.
3. **Session correctness (1 day):** BUG-02 (401 vs 503), SEC-07 (deleted/rejected status, real deletion), SEC-16 (`token_version`).
4. **Database exposure (½ day):** SEC-10 RLS-on/no-policy migration + revoke grants. Test in a Supabase branch or staging project first. The backend connects as the table owner, so it is unaffected.
5. **Private documents (3–4 days):** SEC-04. Introduce `GET /files/<id>` (auth plus ownership/admin check) that returns a signed URL; switch the bucket to private; migrate stored URLs to object paths; update the Flutter document viewers (`in_app_document_viewer.dart`, `cors_image_*`) to request signed URLs. Keep a read-compat shim for old URLs during rollout.
6. **Hardening (2 days):** SEC-15 email change OTP, SEC-17 IP-header trust and per-account lockout, SEC-18 generic errors, SEC-12 admin MFA (email OTP reuses the existing OTP table and mailer).

**Testing:** a pytest authorisation matrix for every changed route (anon / member / other member / sub-admin without permission / sub-admin with permission / admin), run against a disposable Postgres container in CI. Then a manual regression of admin web flows.

**Architecture note:** nothing here changes the stack. The only structural change is serving documents through signed URLs, which is necessary because public URLs for identity and financial documents can't be made safe.

## Phase 2 — Mobile security & store blockers (≈ 1.5 weeks, overlaps Phase 1)

1. **Release hygiene (1 day):** remove the server-config dialog (SEC-11); release keystore and Play App Signing (BUG-03); final application ID (AND-03); `targetSdk 36` (AND-01); Xcode 26 build (IOS-01).
2. **iOS config (½ day):** link entitlements + Push capability + APNs key (BUG-01); remove ATS exceptions, the local-network key and unused background modes (IOS-03, IOS-10); privacy manifest (IOS-14).
3. **Permissions (½ day):** remove camera/`mobile_scanner` from the mobile build, or expose staff check-in (IOS-11); move the notification prompt after login (BUG-07).
4. **Messaging safety (2–3 days):** report/block + admin moderation list, or restrict to Secretariat (IOS-05/AND-05).
5. **Payments policy (1–2 days):** implement the CTI online-course decision for iOS (IOS-07).
6. **Client data protection (2 days):** token only in secure storage (SEC-13); encrypt the Hive cache (PERF-08); crash reporting (BUG-04). SEC-14 (device token for biometrics) needs a small backend endpoint; schedule it here if time allows, otherwise Phase 4.
7. **Device form factors (1 day):** portrait lock on phones; apply the iPad decision; edge-to-edge and 16 KB checks (RESP-01/02, AND-06/07).

**Exit criteria:** internal-track AAB and TestFlight builds install, push works on both platforms, and the core flow runs end to end against production with the demo account.

## Phase 3 — Compliance content & listing (parallel, ≈ 2–3 weeks elapsed, mostly non-developer)

- Rewrite the privacy policy and terms with legal review; publish public URLs; publish the web deletion-request page.
- Fill in Play Data safety, Apple App Privacy, content rating and age rating from the data inventory in `CUBAG_STORE_READINESS.md §6`.
- Commission the logo master; regenerate icons/splash; produce screenshots and the feature graphic from the demo account.
- Remove invented fallbacks on certificates; label static data (BUG-10/11).

## Phase 4 — Functional hardening & test net (≈ 1 week)

- Make CI real: un-ignore `.github/`, pin tool versions, run backend and Flutter tests on every PR.
- Replace the placeholder widget test with tests for login, registration steps, router gating and error mapping.
- Move rating recalculation off read paths (BUG-09).
- **Device smoke test** (script in the checklist) on: iPhone SE (3rd gen), a large iPhone (Pro Max), a small/older Android (~360 dp, Android 10–12), an Android 15/16 gesture-nav device, plus iPad if kept. Record results in the checklist.

**Then submit:** Play internal → closed/production; TestFlight → App Store review. Budget 1–3 review rounds; Apple review notes must include the demo account and an explanation of the membership/payment model.

## Phase 5 — Database & operations (≈ 1 week, after first submission)

- Versioned migrations; remove runtime DDL (DB-01).
- Index review from real query stats (DB-03); Supabase pooler (DB-05).
- One deployment target; prune configs (DB-07).
- Optional low-cost reliability: Upstash Redis for cache and rate limits (DB-06), so limits survive deploys and a second machine becomes possible.

**Cost note:** none of these require paid infrastructure beyond what's in use. Redis on Upstash's free tier and a Fly VM bump to 1 GB are the only likely additions.

## Phase 6 — UI/UX, accessibility & responsiveness (ongoing, from week 5)

Work screen by screen in this order (most-used first): login → register/OTP → application documents → dashboard → payments → compliance centre → licence renewal → profile/settings → messaging → notifications → events/courses → the rest.

For each screen, in one PR:
1. Replace hard-coded colours/sizes with theme tokens (UI-01); fix contrast (UI-02).
2. Add semantics/tooltips (UI-03).
3. Check keyboard, safe areas and small/large phones (RESP-03/05); flexible grids (RESP-04).
4. Use the shared error/empty/loading components (UI-09/10).
5. Verify at 130% text scale before raising the global cap (UI-04).

Preserve the brown/orange brand. The goal is consistency and legibility, not a new look.

## Phase 7 — Cleanup & optional (as capacity allows)

Remove dead code (landing page, unused WhitsunPay client, Worker, telemetry stub); R8; signed verification QR; staging environment; ARB strings.

---

## Working agreement for implementation

- One checklist ID (or a tight group) per PR; update `CUBAG_MASTER_CHECKLIST.md` status in the same PR.
- Every security fix ships with an automated test that would have caught it.
- No sweeping refactors bundled with fixes; refactor only the code being changed.
- Deploy backend fixes behind backwards-compatible responses, so the live app keeps working until the new mobile build is out.
- Re-run the authorisation matrix and the device smoke test before each store submission.

## Recommended first batch (awaiting your approval)

If you approve, I'd start with **Phase 1, steps 1–3**: complaints/GDPR/settings authorisation, the certificate and proxy endpoints, the 401/503 fix, and deleted-account handling. That's about 2–3 days of work, entirely backend, with tests. It closes four of the five Critical security findings (SEC-01, 02, 03, 05) plus SEC-06, SEC-07, SEC-19 and BUG-02, none of which depend on your Phase 0 checks. SEC-04 (private documents) needs the Supabase bucket check first.
