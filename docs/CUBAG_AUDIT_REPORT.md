# CUBAG — Master Project Audit Report

**Audit date:** 10 November 2026
**Scope:** `CUSTOMS/` repository: `cubag_flutter/` (Flutter app — Android, iOS, web), `cubag-backend/` (Flask API on Fly.io/Render + Supabase Postgres & Storage), `whitsun-proxy-worker/` (Cloudflare Worker), deployment configs.
**Method:** Static, read-only code inspection. No project files were modified.

> **What this audit did NOT do.** No code was executed, no tests were run, no builds were produced, and no live server, database, Supabase dashboard or store console was accessed. The device workspace was not available during the audit, and neither Flutter nor the backend's Python dependencies were installed in the audit environment. Every finding below is labelled:
> - **Confirmed (code)** — the defect is directly visible in the source; the failure path was traced by reading the code. It has not been reproduced at runtime.
> - **Potential risk** — depends on configuration, data, or runtime behaviour that could not be inspected. Each one says what to check.

---

## 0. Executive summary

CUBAG is a substantial, feature-rich product: ~94,600 lines of Dart across 66 pages and 22 components, and ~21,700 lines of Python across 23 route modules (~220 endpoints). A lot is already done well: parameterised SQL everywhere I looked, server-side fee validation, ownership checks on most member endpoints, OTP attempt limiting, HMAC-verified payment webhook, an in-app account-deletion entry point, a privacy policy screen, and an offline-friendly cache layer.

The app is **not ready for store submission yet**. The blockers fall into three groups:

1. **Security / data-isolation defects that any registered user or anonymous visitor can exploit** (SEC-01 … SEC-08). The most serious: every logged-in member can read and edit **all complaints, including complainants' names, emails and phone numbers**; anyone on the internet can download an official **"Certificate of Licensure & Standing" PDF for any member ID**, including pending or suspended members; an unauthenticated **open proxy (SSRF)** endpoint; and sensitive uploads (receipts, compliance documents) are served from **public URLs with no access control**.
2. **Store configuration blockers**: Android release builds currently fall back to the **debug signing key**; Android `targetSdk` must be **API 36** (Google Play requirement since 31 Aug 2026); iOS **push entitlements are not linked** in the Xcode project; **ATS is disabled**; a **developer "Configure Server Connection" dialog with a hard-coded LAN IP** is reachable from the production login screen; and the source logo is a 237×229 JPEG upscaled to the 1024×1024 store icon.
3. **Compliance content gaps**: the privacy policy is in-app only (stores need a public URL), makes security claims the system does not meet (e.g. "AES-256 data storage", "PCI-DSS"), and omits third-party processors; member-to-member messaging has no report/block (Apple 1.2 / Play UGC policy); account deletion is a soft-delete that leaves a login path open.

Fixing **P0** items is roughly 2–3 focused weeks for one developer (see the roadmap). None of them requires re-architecting the app.

### Findings at a glance

| Category | Critical | High | Medium | Low |
|---|---|---|---|---|
| A. Security | 5 | 7 | 8 | 4 |
| B/C. Functional bugs | 1 | 5 | 6 | 1 |
| D/E. UI/UX & responsive | — | 5 | 10 | 4 |
| F. Database/backend | — | 3 | 5 | 2 |
| G. Performance | — | 1 | 6 | 4 |
| H. Apple rejection risks | 6 | 6 | 4 | — |
| I. Google Play rejection risks | 4 | 4 | 3 | — |

---

## 1. Project discovery (Phase 1)

### 1.1 Technology stack

| Layer | Technology | Evidence |
|---|---|---|
| Mobile/web client | Flutter (Dart SDK `^3.11.5`), Material 3, `go_router` 17, `provider`, `dio`, Hive cache, `flutter_secure_storage`, Firebase Messaging, `local_auth`, `socket_io_client`, `mobile_scanner`, `webview_flutter`, `fl_chart`, `pdf`/`printing` | `cubag_flutter/pubspec.yaml` |
| Backend API | Flask 3.0.3, Flask-JWT-Extended 4.6, Flask-SocketIO (threading), APScheduler, Flask-Caching (SimpleCache or Redis), psycopg2 pool, ReportLab, firebase-admin, Resend/SMTP, Sentry | `cubag-backend/requirements.txt`, `server.py` |
| Database | Supabase Postgres, accessed directly via `DATABASE_URL` (no ORM, no migration tool). Schema created at runtime: 40 `CREATE TABLE` in `config/db.py` + ~65 `CREATE TABLE IF NOT EXISTS`/`ALTER TABLE` inside route handlers | `config/db.py`, `routes/*.py` |
| File storage | Supabase Storage (public bucket URLs) with local-disk fallback served by Flask | `file_storage.py` |
| Payments | WhitsunPay (MoMo) via backend + webhook; manual bank-slip upload; separate Cloudflare Worker proxy | `routes/payments.py`, `whitsun-proxy-worker/` |
| Real-time | Socket.IO rooms (`member_<id>`, `admins`) | `server.py:405-444` |
| External data | aisstream.io (AIS vessels), RSS news worker | `ais_stream.py`, `routes/news.py` |
| Hosting | Fly.io (`fly.toml`, 1 shared CPU / 512 MB, single machine) **and** Render (`render.yaml`) — two deployment definitions coexist; client defaults to `https://cubag-api-server.fly.dev/api/v1` | `fly.toml`, `render.yaml`, `api_service.dart:63` |
| Web frontend | Flutter web build served by Flask SPA catch-all; also Netlify/Render static configs | `server.py:740-777`, `netlify.toml` |
| CI | GitHub Actions workflow exists but `.github/` is in `.gitignore`, so it is not in the repo and never runs | `.gitignore:37`, `.github/workflows/ci.yml` |

### 1.2 Application structure

- **Public routes (no login):** splash, login, register, OTP/verify-email, forgot/reset password, public member directory, member verification, payment-receipt verification, guest services (incl. CTI course MoMo payment), complaints portal & tracking.
- **Member shell (bottom nav / drawer, `StatefulShellRoute`):** dashboard, announcements, cargo schedules, engagement, events, compliance centre, membership services, live data, messaging, networking, notifications, menu, payment history, payments, profile, settings, surveys, tasks, vessel movements, CTI courses, licence renewal; plus onboarding page `/application-documents`.
- **Admin shell (`/admin/*`, 25 pages):** **web-only by design** — on Android/iOS any admin route redirects to `/admin-unavailable` ("Admin Portal Restricted") (`core/router.dart:147-150, 858`).
- **Onboarding gate:** members whose status is not active/approved *or* whose registration fee is unpaid are locked to documents/compliance/payments/settings/profile (`core/router.dart:152-184`).

### 1.3 Dead code / technical debt inventory

| Item | Evidence | Note |
|---|---|---|
| `landing_page.dart` — 7,485 lines (285 KB), largest file in app | Not referenced by the router; `/landing` redirects to `/login` | Dead code; tree-shaken from the binary but a large maintenance burden. Confirm intent, then archive. |
| `public_home_page.dart` | Not routed | Dead. |
| `services/whitsun_pay_service.dart` | No references; default URL is `https://cubag-whitsun-proxy.REPLACE_WITH_ACCOUNT.workers.dev` | Unfinished/abandoned client-side payment path. |
| Dark theme | `AppTheme` defines dark colours; `main.dart` forces `ThemeMode.light`, no `darkTheme` passed; many pages contain `isDark ? … : …` branches that never run | Dead branches. |
| `_upload_path_is_sensitive()` | Defined at `server.py:633`, never called | A security control that was written but never wired in (see SEC-04). |
| Duplicate API surface | Every blueprint registered twice (`/api/v1/...` and `/api/...`) plus `/public/*` aliases | Doubles the attack surface to review; keep only if old web builds still need it. |
| Hard-coded vessel "registry" with June 2026 ETAs | `server.py:582-605` | Static data that will look stale/wrong to users. |
| Static market "intelligence" defaults (bunker prices, port congestion, Red Sea alerts) | `data/intelligence.json`, `routes/intelligence.py` | Shown whenever admins have not updated it. |
| Very large page files (payments 4,524 lines; admin compliance 3,381; admin payments 2,979) | `lib/pages/` | Hard to test and review; split by section when touched. |
| Tests | `test/widget_test.dart` is `expect(true, isTrue)`; backend tests require a live DB login and are skipped otherwise | Effectively no automated regression safety net. |

---

## A. Critical security vulnerabilities (and all security findings)

Severity scale: **Critical** = exploitable now by an ordinary user or anonymous visitor, with data exposure, fraud or integrity impact. **High** = serious but needs a privileged role, a specific configuration, or chaining. **Medium/Low** = hardening.

### SEC-01 — Every logged-in member can read all complaints, including complainants' personal data — **Critical, Confirmed (code)**
- **File:** `cubag-backend/routes/complaints.py:463-516` (`list_complaints`)
- **Evidence:** the route has only `@jwt_required()`; no role or permission check. It returns `name, email, phone, target_entity, subject, description, resolution_notes, assigned_to` for up to 100 complaints and supports `?search=`.
- **Impact:** any registered account (even `pending`) can see who complained about which broker, with contact details. Complaints are a disciplinary/grievance channel, so this exposes complainants to retaliation. It is also a data-protection breach.
- **Fix:** add `@sub_admin_required('complaints')` (add the `complaints` key to `ALL_PERMISSIONS`), or restrict to full admins. Return 403 for members.
- **Test:** member token → `GET /api/v1/complaints` must return 403; admin → 200.

### SEC-02 — Any logged-in member can change the status and resolution of any complaint — **Critical, Confirmed (code)**
- **File:** `routes/complaints.py:519-566` (`update_complaint_status`)
- **Evidence:** `@jwt_required()` only; updates `status, resolution_notes, assigned_to, priority` by complaint ID. IDs are `CMP-<year>-<5 random digits>` (`_generate_complaint_id`, line 258) — 90,000 possibilities per year, and SEC-01 lists them anyway.
- **Impact:** a broker named in a complaint can mark it "Resolved" with fake notes; the public tracking page will then show that "official" resolution.
- **Fix:** same permission decorator as SEC-01; log to audit log.
- **Test:** member token → `PUT /api/v1/complaints/<id>/status` → 403.

### SEC-03 — Unauthenticated official certificate generation for any member ID, regardless of status — **Critical, Confirmed (code)**
- **File:** `routes/members.py:1040-…` (`generate_certificate_pdf`)
- **Evidence:** no auth decorator; `SELECT … FROM members WHERE id = %s` with **no status filter**; the PDF states the member "is a duly registered, licensed, and active … Broker of CUBAG", with president and secretary-general signatures. If no licence number exists it **writes one to the database** (`UPDATE members SET license_number …`) — a GET request with a side effect, triggerable by anyone.
- **Impact:** anyone can obtain an authentic-looking certificate for pending, rejected, suspended or deleted accounts, and enumerate every member's name and company by iterating IDs. This undermines the association's verification function, which is the product's core trust feature.
- **Fix:** require JWT; allow only the owner or an admin; require `status='active'` and good standing; remove the licence auto-assignment from this endpoint (assign licence numbers only in the admin approval flow); add a verification QR/URL that resolves to `/verify-member`.
- **Test:** anonymous → 401; member A for member B → 403; owner who is pending → 403; owner who is active → 200; DB unchanged after the call.

### SEC-04 — Sensitive uploads (receipts, compliance & member documents) are publicly downloadable — **Critical, Confirmed (code)**
- **Files:** `server.py:628-689` (`serve_uploads`), `file_storage.py:88`
- **Evidence:**
  - `_require_jwt_for_sensitive_upload()` despite its name only checks for `..`; it never verifies a JWT. `_upload_path_is_sensitive()` is never called. Files are served with `Access-Control-Allow-Origin: *` and `Cache-Control: public`.
  - Supabase uploads return `…/storage/v1/object/public/<bucket>/…`, which only works if the bucket is **public** — so every receipt, Ghana-Card-type ID, tax clearance and compliance document is readable by anyone holding the URL, forever.
  - Uploaded personal documents are also **committed to git** (`cubag-backend/uploads/compliance_docs/1/*`, `uploads/avatars/*`).
- **Mitigating factor:** filenames include a random UUID, so URLs are not guessable. But URLs leak through logs, admin exports, the client's Hive cache, screenshots and email, and they never expire.
- **Fix:** make the Supabase bucket private; store the object *path* (not a public URL); serve documents through an authenticated endpoint that checks owner/admin and returns a short-lived signed URL (Supabase `createSignedUrl`, e.g. 5 minutes). For local fallback, enforce JWT and ownership in `serve_uploads`. Remove personal files from the repository and purge them from git history.
- **Test:** anonymous request for an existing receipt URL → 401/403; owner → 200; signed URL expires.

### SEC-05 — Unauthenticated open proxy / SSRF at `/api/v1/news/proxy-image` — **Critical, Confirmed (code)**
- **File:** `routes/news.py:353-365`
- **Evidence:** `requests.get(url, stream=True)` on any user-supplied URL, no auth, no scheme/host allow-list, no private-IP check, and the upstream `Content-Type` is passed through. (A properly hardened version already exists at `routes/uploads.py:118-171` — this one was simply never locked down.)
- **Impact:** server-side request forgery against internal/Fly-private addresses; the API host can be used as an anonymous open proxy; and because the Flutter web app is served from the same origin, an attacker can make the API serve `text/html` content from their own server under CUBAG's domain (phishing / script injection on the web app origin).
- **Fix:** delete this endpoint and point callers at the hardened `/uploads/proxy`, or apply the same allow-list + private-IP block + `image/*` content-type enforcement + auth.
- **Test:** `?url=http://169.254.169.254/` and `?url=https://example.com/page.html` → 400/403.

### SEC-06 — Any sub-admin, whatever their permissions, can export any member's full data, approve permanent data deletion, and change licence fees — **High, Confirmed (code)**
- **Files:** `routes/gdpr.py:70, 122, 150, 172`; `routes/compliance_settings.py:24, 64`
- **Evidence:** these routes use `@admin_required`, which admits `sub_admin` (`utils.py:458`), and they have no further permission check (unlike `sub_admins.py`, `admin.py /audit-log` and `/dashboard`, which do check correctly).
- **Fix:** restrict GDPR routes to `admin`/`super_admin`, or add a dedicated `gdpr` permission; use `@sub_admin_required('fees')` or `('settings')` on compliance settings.
- **Test:** sub-admin with only `events` → 403 on each route.

### SEC-07 — Deleted accounts can still log in, and existing tokens keep working — **High, Confirmed (code)**
- **Files:** `routes/auth.py:1594-1622` (`delete_account`), `routes/auth.py:388-445` (`login`), `server.py:321-373`
- **Evidence:** deletion sets `status='deleted'`, prefixes the email and nulls the phone, but keeps `agency_code`, `license_number` and `password_hash`. Login also accepts agency code or licence number and only blocks `suspended`/`inactive`. `enforce_account_status` also blocks only those two values.
- **Impact:** a "deleted" user can sign back in with licence number + password, and any existing token stays valid until it expires (48 h). The store requirement is that deletion actually deletes the account.
- **Fix:** block `deleted` (and `rejected`) in both places; on deletion, also null out `password_hash`, `agency_code`, `license_number` and `fcm_token`; queue removal of documents and photos; keep only records you are legally required to retain (payments) and document that in the privacy policy.

### SEC-08 — Unauthenticated Cloudflare Worker injects live payment-gateway credentials for any caller — **High, Potential risk (if deployed)**
- **File:** `whitsun-proxy-worker/index.js`
- **Evidence:** forwards any method and path to `developer.whitsun.dev` with `x-client-id`/`x-api-key` from Worker secrets; no caller authentication, no path allow-list, `Access-Control-Allow-Origin: *`. The Flutter client that would use it (`whitsun_pay_service.dart`) is unused.
- **Impact if deployed:** anyone who learns the worker URL can call any WhitsunPay API as CUBAG (initiate collections, read transactions, possibly payouts).
- **Fix:** check in the Cloudflare dashboard whether `cubag-whitsun-proxy` is deployed. If it is, delete it, then rotate the WhitsunPay API key. Keep all gateway calls on the backend.

### SEC-09 — Credentials and secrets hygiene — **High, Confirmed (config) / needs owner action**
- `render.yaml` states that `SECRET_KEY`, `JWT_SECRET_KEY`, `DATABASE_URL`, `SMTP_PASS`, WhitsunPay keys, `SUPABASE_SERVICE_KEY` and `AIS_API_KEY` *"were previously committed in plaintext and are now in git history … ROTATE every one of them"*. Whether rotation happened cannot be verified from code. **Treat as not done until confirmed.**
- `.git/config` on this machine contains a credential embedded in the `origin` remote URL (value not reproduced here). Remove it, revoke that token on GitHub, and use a credential helper or SSH.
- Firebase project ID is `schb-8cd66`, which does not look like a CUBAG-owned project. Confirm CUBAG controls this Firebase project and its service account.
- Outbound email is configured to send as unrelated domains (`Supportteam@cryptoplextrades.com` in `fly.toml`, `support@winningedgeinvestment.com` in `render.yaml`, default `eaap2026@eventslabs.org`). Members receive OTPs and password resets from domains that are not CUBAG's: a phishing-signal and deliverability problem, and a trust issue. Send from a CUBAG domain with SPF/DKIM/DMARC.

### SEC-10 — Supabase tables may be readable through the public REST API — **High, Potential risk (must verify)**
- **Evidence:** all tables are created in `public` by raw SQL; there is no `ENABLE ROW LEVEL SECURITY` anywhere in the codebase. On Supabase, `public` tables are exposed through PostgREST to the `anon`/`authenticated` roles by default. If RLS is off, anyone with the project URL and the anon key (which is not secret by design) can query `members` — including `password_hash` — and `payments`, `complaints`, and so on.
- **Verify:** Supabase Dashboard → Advisors → Security (look for "RLS disabled in public"), or run `select relname, relrowsecurity from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r';`.
- **Fix (cheap and safe for this architecture):** since only the backend should touch the DB, enable RLS on every table with **no policies** (the backend's direct Postgres role bypasses RLS as owner), and/or `revoke all on all tables in schema public from anon, authenticated;`. Alternatively, move the tables to a non-exposed schema.

### SEC-11 — Production login screen exposes a developer "Configure Server Connection" dialog — **High, Confirmed (code)**
- **File:** `cubag_flutter/lib/pages/login_page.dart:92-260, 623-640`; `services/api_service.dart:18-27, 79-93`
- **Evidence:** whenever a login error contains "reach", "server" or "connection", a red link opens a dialog offering "LAN IP (192.168.4.127)" and a free-text server URL; the URL is persisted as `custom_api_url` and **overrides the production URL on next launch**, and every subsequent request (including credentials and the bearer token) goes there.
- **Impact:** a social-engineering vector ("set your server to X") that captures passwords; it also looks unfinished to store reviewers, who often test on poor networks.
- **Fix:** compile it out of release builds (`if (kDebugMode)`), and ignore `custom_api_url` in release builds.

### SEC-12 — Admin accounts have no multi-factor authentication — **High, Confirmed (code)**
- Admins approve members, verify payments, export data and run deletions with password-only login (8-hour token). Add TOTP or email-OTP step-up for `admin`/`super_admin`/`sub_admin`.

### SEC-13 — JWT stored in plaintext SharedPreferences alongside secure storage — **Medium, Confirmed (code)**
- **File:** `lib/utils/session_storage_stub.dart:49` (`prefs.setString('cubag_token', secureToken)`) and `setString()` (writes every key, including the token, to SharedPreferences before also writing secure storage).
- **Fix:** never write `cubag_token` to SharedPreferences; delete any legacy copy on startup.

### SEC-14 — Biometric login stores the raw password — **Medium, Confirmed (code)**
- **File:** `lib/services/biometric_service_native.dart:42-45`. The password is kept in the keychain/keystore (encrypted at rest, but not bound to a biometric access control), and replayed to `/auth/login`. `isBiometricAvailable()` returns `true` on a platform exception.
- **Fix:** store a server-issued, revocable device refresh token instead of the password, or at minimum a keychain item with biometry access control.

### SEC-15 — Email can be changed without re-verification — **Medium, Confirmed (code)**
- `routes/auth.py:1318-1380`: `PUT /auth/profile` sets a new email immediately. Combined with password reset by email, a briefly hijacked session becomes a permanent takeover. Require OTP to the new address and notify the old one.

### SEC-16 — Tokens are not revoked on password change/reset; no refresh-token model — **Medium, Confirmed (code)**
- Members get 48-hour tokens and admins 8-hour tokens (`auth.py:482-488`); `fly.toml` also sets a 7-day default. There is no `token_version`/blocklist, so a stolen token survives a password reset. Add `token_version` to `members`, embed it in the JWT, and check it in `enforce_account_status` (already a per-request DB/cache lookup, so the extra cost is negligible).

### SEC-17 — Rate limiting can be bypassed by spoofed headers when not on Fly — **Medium, Confirmed (code)**
- `config/rate_limit.py:20-35` trusts `Fly-Client-IP` and `CF-Connecting-IP` whenever present. On Fly the edge sets `Fly-Client-IP`, but on Render (also configured), or if Fly is ever bypassed, a client can rotate these headers to get unlimited login/OTP attempts. Rate-limit state is also in-process (`SimpleCache`) and resets on every deploy. There is no per-account login lockout.
- **Fix:** trust only the header of the platform actually in use (from an env var); add a per-identifier login failure counter similar to the existing OTP counter.

### SEC-18 — Internal error text returned to clients — **Medium, Confirmed (code)**
- About 50 handlers return `jsonify({'message': str(e)})`, and the global handler (`server.py:791-802`) returns `str(e)`. This can leak SQL, table/column names and paths. Return a generic message plus a correlation ID; keep details in logs/Sentry.

### SEC-19 — Compliance payment webhook fails open when the secret is unset; no replay protection — **Medium, Confirmed (code)**
- `routes/compliance.py:1775-1795`: `if secret:` — no secret means every unsigned request is accepted, and there is no timestamp check (unlike `/payments/webhook`, which fails closed and checks timestamps). Combined with `store-payment-ref`, a member could move their own application to `under_review` with an arbitrary `amount` if the secret were ever missing. Reuse the hardened verification from `payments.py:1497-1540`.

### SEC-20 — Payment amount accepted from client when description matches no fee rule — **Medium, Potential risk**
- `config/payment_validation.py:391-404`: if the free-text `description` matches no fee rule or keyword, `client_amount` is accepted. Installments for registration/package fees accept any amount from GHS 0.01. Whether a partial or arbitrary payment can unlock membership status depends on downstream approval logic, which needs targeted testing. Prefer: client sends a `fee_id`/`bill_id`, server derives the amount; never derive pricing from free text.

### SEC-21 — Upload content-type trusted from client — **Low, Confirmed (code)**
- Extensions are allow-listed (good), but the stored Content-Type comes from the client (`file_storage.py:150-153`), and there is no magic-byte check. Set Content-Type from the validated extension and sniff the first bytes.

### SEC-22 — Wide-open CORS and Socket.IO origins — **Low, Confirmed (config)**
- `server.py:201-207` (`origins="*"`), `socket_instance.py`. Acceptable with bearer tokens; restrict to the real web origins to reduce abuse of the web app API from other sites.

### SEC-23 — Registration lets applicants choose their own fee category/scale — **Low, Potential risk**
- `auth.py:301-305` takes `memberScale`/`feeCategory` from the request. Confirm admins re-check this at approval, since it changes what the member is billed.

### SEC-24 — Logging of PII — **Low, Confirmed (code)**
- `payments.py` logs the full payment request body (`[Payments] New request … {data}`), which includes phone numbers; `server.py:188` logs all env var *names* on startup failure (names only — acceptable). Mask phone numbers and account numbers.

**Positive security observations:** SQL is parameterised throughout (the f-strings found only join fixed fragments); OTPs use `secrets`; per-email OTP failure counters exist; the main WhitsunPay webhook verifies HMAC with constant-time compare and a timestamp; the image proxy in `uploads.py` is correctly hardened; most member endpoints check ownership (`compliance/applications/<id>`, `payments/status/<id>`, `payments/verify/<ref>`, notifications, tasks); sub-admin management correctly requires full admin; the backend refuses to boot with default secrets in production; security headers and HSTS are set.

---

## B. Critical functional bugs

### BUG-01 — iOS push notifications will not be delivered — **Critical (for a notification-driven app), Confirmed (config)**
- **Evidence:** `ios/Runner/Runner.entitlements` and `RunnerRelease.entitlements` exist with `aps-environment`, but `project.pbxproj` contains **no `CODE_SIGN_ENTITLEMENTS` setting**, so they are not applied to the build. Firebase Messaging on iOS requires the Push Notifications capability (and an APNs key uploaded to Firebase).
- **Fix:** Xcode → Runner target → Signing & Capabilities → add "Push Notifications" and "Background Modes › Remote notifications"; point Debug at `Runner.entitlements` and Release at `RunnerRelease.entitlements`; upload the APNs auth key to Firebase.
- **Test:** TestFlight build on a real device receives a test push in background and killed states.

## C. High-priority bugs

### BUG-02 — Expired or invalid tokens produce "Unable to verify account status" (503) instead of signing the user out — **High, Confirmed (code)**
- **File:** `server.py:321-373`. `verify_jwt_in_request(optional=True)` still raises on an *expired or invalid* token; the generic `except` turns that into **503**. The client only logs out on **401** (`api_service.dart:190-202`). Members recover when `/auth/me` is next called (that path is exempt and returns 401), but until then every screen errors. Web admins are hit harder. This will happen to every user at once when you rotate `JWT_SECRET_KEY` (SEC-09).
- **Fix:** catch `ExpiredSignatureError`/`InvalidTokenError`/`JWTDecodeError` separately and return 401; keep 503 only for DB failures.
- **Test:** call any member endpoint with an expired token → 401 → app routes to login.

### BUG-03 — Android release builds silently use the debug signing key — **High, Confirmed (config)**
- **File:** `android/app/build.gradle.kts:55-60`; there is no `android/key.properties` in the project. Play Console rejects debug-signed bundles. Create an upload keystore (keep it out of git, back it up), add `key.properties`, enrol in Play App Signing, and make the release build **fail** instead of falling back to debug.

### BUG-04 — Errors are swallowed globally, so crashes are invisible — **High, Confirmed (code)**
- **File:** `lib/main.dart:39-45`. Both `PlatformDispatcher.onError` and `FlutterError.onError` only `debugPrint`, and `debugPrint` is silenced in release (`main.dart:51-53`). There is no client crash reporting. Add Firebase Crashlytics (the Firebase project already exists) or `sentry_flutter` (the backend already uses Sentry).

### BUG-05 — Account status `deleted`/`rejected` not handled (see SEC-07) — **High, Confirmed (code)**

### BUG-06 — CI never runs and would fail if it did — **High (process), Confirmed (config)**
- `.github/` is git-ignored, and the workflow pins Flutter `3.19.x` while `pubspec.yaml` requires Dart `^3.11.5` (Flutter 3.19 ships Dart 3.3), and Python 3.9 while the Dockerfile uses 3.11. Un-ignore `.github/`, pin Flutter to the version you build with, and use Python 3.11.

### BUG-07 — Notification permission requested at cold start, before login — **Medium, Confirmed (code)**
- `main.dart:128` → `PushNotificationService().initialize()` → `requestPermission()` plus Android 13 `requestNotificationsPermission()` on first launch, before the user knows what the app is. Users who deny can't easily be re-asked on iOS. Move the request to after login (the `requestPermissionsAndSyncToken()` call in `dashboard_page.dart:54` is already the right place) with a short explainer.

### BUG-08 — Certificate endpoint mutates data on GET — **Medium, Confirmed (code)** (see SEC-03)

### BUG-09 — `get_member` performs writes and rating recalculation on every profile view — **Medium, Confirmed (code)**
- `routes/members.py:849-950` assigns licence numbers and runs `calculate_and_update_member_rating` + `commit` on reads; login also spawns a thread for the same recalculation. Concurrent requests can race. Move rating recalculation to the scheduler or to the write events that change inputs (payment approved, document reviewed).

### BUG-10 — Static/stale data presented as live — **Medium, Confirmed (code)**
- Vessel registry with fixed June 2026 ETAs (`server.py:582-605`); default "intelligence" (bunker prices, congestion, alerts) in `data/intelligence.json`. Label as "reference/sample" or hide until real data exists (also an Apple 2.3 accuracy concern).

### BUG-11 — Hard-coded certificate/verification fallbacks — **Medium, Confirmed (code)**
- Certificates fall back to company name `'HART LOGISTICS'`, port `'KIA Air Cargo'`, and member type `'Individual Broker'`; public verification falls back to `valid_until '31 Dec 2026'` and generates `CUBAG-2026-xxxx` / `LIC-CUBAG-2026-xxxx` numbers on the fly (`members.py:977-984`, certificate code ~1130-1170). Signatory names are hard-coded. Fail instead of inventing values; read signatories and years from settings.

### BUG-12 — Messaging has no length limit, no rate limit, and no recipient validation — **Medium, Confirmed (code)**
- `routes/messages.py:105-130`: any member can message any `other_id` (including non-existent or suspended members), with any text length, at any rate. Validate the recipient, cap length (e.g. 2,000 chars), and rate-limit.

### BUG-13 — Uploaded file stored before ownership check — **Low, Confirmed (code)**
- `compliance.py:808-860` writes the file to storage, then checks the application belongs to the caller; non-owners create orphan files. Check first.

---

## D. UI/UX design improvements

Assessment is from code (no screenshots or device runs were available). Metrics come from a scan of all 88 page/component files.

| ID | Finding | Evidence | Severity | Recommendation |
|---|---|---|---|---|
| UI-01 | **Theme not used as a design system.** 2,384 hard-coded `Color(0x…)` literals and 1,457 `Colors.*` uses across pages, versus a small `AppTheme`/`AppColors` palette. 2,296 hard-coded `fontSize:` values and 1,827 direct `GoogleFonts.*` calls. | metrics scan; e.g. `payments_page.dart` 188 colour literals, 111 font sizes | High | Introduce `ThemeExtension` tokens (surface, onSurface, muted, success/warn/error, radius/spacing scales) and a `TextTheme`-based type scale. Migrate page by page as pages are touched — no big-bang rewrite. |
| UI-02 | **Brand orange fails contrast for text.** `#FF5000` on white = **3.28:1** (WCAG AA needs 4.5:1 for normal text). `textMuted #94A3B8` on white = **2.56:1**, on cream = **2.34:1**. Brown `#6B3E26` on white = 8.97:1 (good). | `core/theme.dart`, `utils/app_colors.dart` | High | Keep orange for fills/large text/icons; use a darker orange (around `#C2410C`, ≈5.2:1) for orange text and links; darken muted text to ≈`#64748B` (4.8:1). |
| UI-03 | **Accessibility labelling is minimal.** Only 54 `Semantics`/`semanticLabel`/`tooltip` usages across 94k lines; icon-only buttons are common. | metrics scan | High | Add `tooltip:` to every `IconButton`, `semanticLabel` to meaningful images, and `Semantics(button: true)` on tappable `GestureDetector`/`InkWell` cards. |
| UI-04 | **Text scaling capped at 115%.** `main.dart:183-190` clamps the system text scaler to 0.85–1.15. This hides overflow bugs but blocks users who need large text (Apple and Android accessibility expectations). | `main.dart:183-190` | Medium | Raise the max to at least 1.3 now and to 2.0 once layouts are fixed; fix overflowing cards rather than clamping. |
| UI-05 | **Inconsistent corner radii.** 1,599 `BorderRadius.circular(n)` calls with many values. | metrics scan | Medium | Define a 3-step radius scale (e.g. 8/12/20) and use tokens. |
| UI-06 | **Two font strategies at once.** Inter and Outfit TTFs are bundled under `assets/fonts/`, but no `fonts:` family is declared in `pubspec.yaml`, and `GoogleFonts.config.allowRuntimeFetching = true` downloads fonts from Google at runtime. First launch offline or on poor networks will render fallback fonts and then reflow. | `pubspec.yaml`, `main.dart:47-48` | Medium | Declare bundled fonts in `pubspec.yaml` (or name them the way `google_fonts` expects) and set `allowRuntimeFetching = false` in release builds. This also avoids an undisclosed third-party network call. |
| UI-07 | **Dark mode half-built.** Dark palette and `isDark` branches exist; the app is forced light. | `main.dart`, `settings_page.dart:235-239` | Low | Either finish it (pass `darkTheme`, honour system setting) or remove the dead branches. Light-only is acceptable for v1. |
| UI-08 | **Store icon and splash are low resolution.** Source `assets/images/logo.jpeg` is **237×229 px** (not square), upscaled to the 1024×1024 iOS marketing icon and all Android launcher sizes; the splash uses the same JPEG on white. | `pubspec.yaml` `flutter_launcher_icons`, image inspection | High (brand + store) | Get a vector/SVG or ≥1024 px square master of the logo; create an Android adaptive icon (foreground + background) and an Android 12 splash icon with safe-zone padding; regenerate. |
| UI-09 | **Error feedback is inconsistent.** A shared `FetchErrorView` exists but most pages use ad-hoc SnackBars/containers; backend messages (including raw exception text, SEC-18) are shown verbatim. | `components/fetch_error_view.dart`; pages | Medium | Standardise on one error view, one SnackBar helper, and a mapping from status codes to human messages. |
| UI-10 | **Loading states are inconsistent.** Both `shimmer_loader.dart` and `skeleton_loader.dart` exist, plus `CircularProgressIndicator` in places. | components | Low | Pick one skeleton style for lists/cards; spinners only for short actions. |
| UI-11 | **"Admin Portal Restricted" screen on mobile.** Admins who log in on the phone hit a dead end. | `router.dart:858+` | Medium | Acceptable for v1, but make it useful: show a link/QR to the web portal and keep any member features usable if the admin is also a member. Make sure store reviewers get a member demo account, not an admin. |
| UI-12 | **Over-long screens.** Payments (4.5k lines), compliance centre, and membership services pack many sections into one scroll. | file sizes | Medium | Break flows into steps or tabs (e.g. Payments → Due now / History / Receipts), which also makes testing easier. |
| UI-13 | **Copy tone.** Some UI text is over-styled ("Real-time financial performance telemetry…", "cryptographic QR verifications", "Executive Multi-Layer Border" in certificate code comments). | various | Low | Plain, direct language reads as more professional for a regulatory body. |
| UI-14 | **`SelectionArea` wraps the whole app.** Every text is long-press selectable, which interferes with taps on cards and lists on mobile. | `main.dart:191-193` | Low | Limit selection to content where copying matters (reference numbers, receipts). |

**Brand identity** (brown `#6B3E26` + orange `#FF5000` on white/cream) is distinctive and should be kept; the work is consistency and contrast, not a redesign.

## E. Responsive design problems

| ID | Finding | Evidence | Severity | Recommendation |
|---|---|---|---|---|
| RESP-01 | **iPad is a supported device** (`TARGETED_DEVICE_FAMILY = "1,2"`), and iPad supports all four orientations, but most member pages have no tablet layout: e.g. `payments_page.dart` (4,524 lines) has **0** `MediaQuery`/`LayoutBuilder`/`Responsive` calls; `compliance_centre_page.dart`, `membership_services_page.dart`, `tasks_page.dart`, `events_page.dart`, `notifications_page.dart`, `settings_page.dart` likewise rely on `maxWidth` boxes only. | `project.pbxproj`, metrics scan | High | Either (a) remove iPad from v1 (`TARGETED_DEVICE_FAMILY = 1`), or (b) commit to iPad: a two-pane layout for list/detail pages and a `NavigationRail` instead of bottom nav at ≥600 dp. Option (a) is cheaper and lower risk for launch. |
| RESP-02 | **iPhone landscape enabled** (`UISupportedInterfaceOrientations` includes landscape) but layouts are portrait-designed. Long forms in landscape on small phones leave about 300 pt of height for content plus keyboard. | `Info.plist` | Medium | Lock phones to portrait for v1 (`SystemChrome.setPreferredOrientations` plus `Info.plist`), unless landscape is a deliberate feature. |
| RESP-03 | **Keyboard overlap risk in sheets/dialogs.** 77 `showDialog`/`showModalBottomSheet` calls and 45 pages with text fields, but only 5 uses of `viewInsets`/`resizeToAvoidBottomInset`. Bottom sheets with fields need `isScrollControlled: true` plus bottom padding of `MediaQuery.viewInsetsOf(context).bottom`. | metrics scan | Medium (potential) | Audit every bottom sheet that contains a `TextField`; add a shared `KeyboardSafeSheet` wrapper. |
| RESP-04 | **Fixed-ratio grids.** Dashboard grids use `crossAxisCount: 2` with fixed aspect ratios (`dashboard_page.dart:1010, 1748`); with longer text or larger fonts, tiles clip. | code | Medium | Use `SliverGridDelegateWithMaxCrossAxisExtent` and intrinsic-height tiles, or `Wrap`. |
| RESP-05 | **Safe areas rely on the scaffold.** Only 15 `SafeArea` uses; pages without an `AppBar` (splash, login, register, verify flows, full-screen viewers) need explicit insets, especially on notched iPhones and Android 15+ edge-to-edge (enforced when targeting API 35+). | metrics scan | Medium (potential) | Test on iPhone SE (3rd gen), iPhone 16 Pro Max, a 360×640 Android, a gesture-nav Android 15/16 device, and an iPad. |
| RESP-06 | **Good foundation exists.** `utils/responsive.dart` has sensible breakpoints (380/600/1024) and helpers, but it is used in only a handful of pages (login 59, licence renewal 36, complaints 23, dashboard 19). | code | — | Reuse it rather than adding a new package. |

**Screens to prioritise for device testing:** login, register (multi-step), OTP, application-documents (onboarding), payments, compliance centre, licence renewal, profile, messaging (keyboard plus list), settings (delete-account dialog).

## F. Database and backend improvements

| ID | Finding | Severity | Recommendation |
|---|---|---|---|
| DB-01 | **No migration system.** Schema is created/altered at app start (`init_db`, 40 tables) and *inside request handlers* (~65 `CREATE TABLE IF NOT EXISTS`/`ALTER TABLE`, e.g. `guest_payments` in `public_initiate_momo`). DDL in hot paths takes locks, slows requests, and hides schema drift. | High | Freeze the current schema into versioned SQL migrations (plain numbered `.sql` files, Alembic, or Supabase migrations), run them at deploy time, and remove runtime DDL. |
| DB-02 | **RLS/exposure not configured** (see SEC-10). | High | Enable RLS with no policies and revoke `anon`/`authenticated` grants. |
| DB-03 | **Only one small index migration** (`supabase_indexes_migration.sql`). Frequent filters (`payments.member_id/payment_ref/status`, `notifications.member_id, deleted_at`, `messages(sender_id, receiver_id, created_at)`, `complaints.complaint_id`, `otp_codes(email,type)`, `LOWER(email)`, `regexp_replace(phone…)`) need index checks. | High | Run `pg_stat_statements` / Supabase Query Performance; add indexes for the top queries, including a functional index on `LOWER(email)`. Login by phone uses `regexp_replace` on every row — store a normalised phone column. |
| DB-04 | **Soft-delete and status semantics are inconsistent** (`deleted`, `deleted_at`, `inactive`, `suspended`, `pending`, `approved`, `active`). | Medium | Define a status enum/check constraint and one helper used by login, `enforce_account_status`, directory and verification. |
| DB-05 | **Connection pool up to 50** (`ThreadedConnectionPool(5, 50)`) on a single gunicorn worker with 8 threads plus background threads. Check the Supabase plan's connection limit; prefer the Supabase pooler (port 6543) in transaction mode. | Medium | Pool max ≈ 10–12; use the pooler URL. |
| DB-06 | **In-process state.** Rate limits, caches, Socket.IO rooms and APScheduler all live in one process, which is why the app must run exactly one machine (`fly.toml`). This is fine for launch traffic but is a single point of failure, and deploys reset rate limits. | Medium | Add Redis (Upstash free tier is enough; the code already supports `REDIS_URL`) for cache/rate limits; move scheduler jobs to a cron-triggered endpoint when you need a second machine. |
| DB-07 | **Two deployment targets** (Fly and Render) with different SMTP settings, regions and URLs; CSP and image proxy allow-lists reference Render/Railway/Fly hosts. | Medium | Pick one (the app points to Fly), delete the other config, and prune allow-lists. |
| DB-08 | **Data retention/GDPR modules exist** (`config/data_retention.py`, `gdpr_compliance.py`) but deletion of storage objects and documents was not visible in `delete_account`. | Medium | Wire account deletion to remove storage objects and personal fields; document retained financial records. |
| DB-09 | **`whitsun` callback URL** points to `onrender.com` in `render.yaml`, while the client uses Fly. | Low | Confirm the webhook URL registered with WhitsunPay matches the live host. |
| DB-10 | **Uploads committed to git** (see SEC-04). | Low | Remove and purge. |

## G. Performance improvements

| ID | Finding | Severity | Recommendation |
|---|---|---|---|
| PERF-01 | **Single small VM runs everything** (API, Socket.IO, AIS websocket stream, RSS worker, APScheduler) on 1 shared CPU / 512 MB, single process with 8 threads. CPU-bound PDF generation (ReportLab) and password hashing block threads. | High | Fine for launch volume; monitor with Sentry performance. First upgrades: 1 GB RAM; consider moving AIS to on-demand rather than a permanent stream. |
| PERF-02 | **Cold-start "wake-up" ping** to the backend on every launch (`main.dart:134-141`) was written for Render free-tier sleeping; Fly is configured always-on. | Low | Remove, or keep only as a cheap health check. |
| PERF-03 | **Runtime Google Fonts fetching** (UI-06) adds network requests and layout shift. | Medium | Bundle fonts. |
| PERF-04 | **Per-request status lookup** in `enforce_account_status` (15 s cache, in-process). | Low | OK; move to Redis if scaling out. |
| PERF-05 | **Images:** 20 `Image.network`/`NetworkImage` uses alongside 20 `CachedNetworkImage`; profile photos and documents are uploaded at original size (up to 10–15 MB). | Medium | Use `CachedNetworkImage` everywhere; downscale/compress images client-side before upload (e.g. max 1600 px, JPEG 80). |
| PERF-06 | **Large lists built eagerly.** 44 `Column(`/`ListView(` in `payments_page.dart`; overall 69 `ListView.builder` uses vs many eager lists. | Medium | Use builders/slivers for any list that can exceed ~30 items (payments, notifications, messages, directory). Add pagination where the API supports it. |
| PERF-07 | **Rating recalculation on reads** (BUG-09). | Medium | Move to events/scheduler. |
| PERF-08 | **Cache-first Hive layer** is good for perceived speed and poor networks, but caches are unencrypted on device and include personal and payment data. | Medium | Encrypt the Hive box (`HiveAesCipher` with a key in secure storage) or exclude sensitive endpoints from caching. |
| PERF-09 | **Socket reconnect on every resume** plus profile refresh — fine, but make sure sockets are closed when backgrounded to save battery. | Low | Disconnect on `paused`, reconnect on `resumed`. |
| PERF-10 | **Global `Cache-Control: no-store`** on every response (`server.py:113-115`) defeats HTTP caching for public, rarely changing endpoints (fees, ports, courses, news). | Medium | Set `max-age` on public GETs. |
| PERF-11 | **Android release build has no R8 shrinking configured.** | Low | Enable `isMinifyEnabled`/`isShrinkResources` with Flutter's ProGuard defaults after testing. |

## H. Apple App Store rejection risks

See `CUBAG_STORE_READINESS.md` for the full matrix with guideline references. Summary:

| ID | Risk | Type | Severity |
|---|---|---|---|
| IOS-01 | Build must use **Xcode 26 / iOS 26 SDK** (required since 28 Apr 2026). | Mandatory | Critical |
| IOS-02 | **Push entitlements not linked** (BUG-01) — notifications are a core feature described to users. | Mandatory for feature | Critical |
| IOS-03 | **ATS disabled** (`NSAllowsArbitraryLoads = true`, `NSAllowsLocalNetworking`) and a **"development backend server"** local-network purpose string. | Mandatory fix (justification required otherwise) | Critical |
| IOS-04 | **Developer server-configuration dialog** in the login flow (SEC-11) — Guideline 2.1/2.3 (unfinished or test functionality). | Mandatory fix | Critical |
| IOS-05 | **Member-to-member messaging without report/block/filter** — Guideline 1.2 (user-generated content). | Mandatory (feature-dependent) | Critical |
| IOS-06 | **Reviewer access**: new accounts are locked until admin approval and fee payment; admins are blocked on mobile. Provide a fully active member demo account and notes. Guideline 2.1. | Mandatory | Critical |
| IOS-07 | **Payments for online CTI courses via MoMo** — online courses are digital services and normally require In-App Purchase (3.1.1); in-person training and association dues/licences are generally real-world services (3.1.3(e)). Needs a product decision. | Depends on functionality | High |
| IOS-08 | **Account deletion is incomplete** (SEC-07) — Guideline 5.1.1(v). | Mandatory | High |
| IOS-09 | **Privacy policy**: needs a public URL in App Store Connect plus in-app access; current text overstates security and omits processors. Privacy "nutrition label" must match actual collection. | Mandatory | High |
| IOS-10 | **Unused background modes** (`fetch`, `processing`) declared without `BGTaskSchedulerPermittedIdentifiers` or use — Guideline 2.5.4. | Mandatory fix | High |
| IOS-11 | **Camera permission** declared for "scan member QR codes for event verification", but the scanner is only reachable from admin pages, which are blocked on mobile — reviewers may flag a permission without a reachable feature. | Recommended | Medium |
| IOS-12 | **Icon quality** (237 px source upscaled). | Recommended | High |
| IOS-13 | **iPad support** declared but layouts not tablet-ready (RESP-01). | Depends (iPad enabled) | High |
| IOS-14 | **No app-level `PrivacyInfo.xcprivacy`**; the app uses required-reason APIs via plugins (UserDefaults via shared_preferences, file timestamps). Plugins ship their own manifests, but an app-level manifest is expected. | Mandatory (privacy manifest rules) | Medium |
| IOS-15 | **Static "market intelligence"/vessel data** shown as live (BUG-10) — 2.3 accuracy. | Recommended | Medium |
| IOS-16 | **Age rating questionnaire** (updated system, required since 31 Jan 2026) — UGC/messaging answers. | Mandatory | Medium |
| — | **Sign in with Apple** is **not required**: the app uses only its own email/phone + password login, no third-party social login. | — | — |

## I. Google Play Store rejection risks

| ID | Risk | Type | Severity |
|---|---|---|---|
| AND-01 | **Target API 36** required for new apps/updates since 31 Aug 2026; `targetSdk = flutter.targetSdkVersion`, so it depends on the Flutter version used. Verify the generated value is 36 or set it explicitly. | Mandatory | Critical |
| AND-02 | **Debug-signed release** (BUG-03). | Mandatory | Critical |
| AND-03 | **Application ID `com.cubag_flutter`** is permanent after first upload and differs from iOS `com.cubag.app`. Change before the first upload if the app is not yet on Play (Firebase `google-services.json` must be regenerated to match). | Decision before first upload | Critical |
| AND-04 | **Data safety form** must declare: name, email, phone, address (digital address), government IDs/tax numbers (TIN, documents), financial info (MoMo numbers, bank details, payment records), photos/files, messages, device IDs/push tokens; data shared with processors (Firebase, Supabase, WhitsunPay, email provider); deletion mechanism (in-app plus a **web deletion URL** — Play requires a web link where users can request deletion without reinstalling). | Mandatory | Critical |
| AND-05 | **UGC policy** for member messaging (report/block, moderation). | Mandatory (feature) | High |
| AND-06 | **Edge-to-edge** is enforced on Android 15+ for apps targeting API 35+; `SystemUiOverlayStyle.systemNavigationBarColor` is ignored there. Check all screens for content under the status/nav bars. | Mandatory behaviour | High |
| AND-07 | **16 KB memory page size** support is required for apps targeting Android 15+ with native code (`mobile_scanner`/ML Kit, `local_auth`, `flutter_secure_storage`, etc.). Verify with the Play Console pre-launch report / APK Analyzer and update plugins as needed. | Mandatory (native libs) | High |
| AND-08 | **CAMERA** permission declared for a feature unreachable on mobile (IOS-11); `RECEIVE_BOOT_COMPLETED`, legacy storage permissions — keep only what is used. | Recommended | Medium |
| AND-09 | **Content rating questionnaire** (messaging = users interact). | Mandatory | Medium |
| AND-10 | **Store listing assets**: 512×512 icon, 1024×500 feature graphic, phone screenshots (and tablet if you declare tablet support). Icon quality issue (UI-08). | Mandatory | High |
| AND-11 | **Closed testing requirement** — newly created *personal* developer accounts must run a closed test (12+ testers for 14 days) before production. **Organisation** accounts are exempt. Register CUBAG as an organisation (D-U-N-S number needed). | Depends on account type | Medium |

## J. Incomplete features

| ID | Feature | Evidence | Status |
|---|---|---|---|
| INC-01 | Client-side WhitsunPay service and Cloudflare Worker | `whitsun_pay_service.dart` (placeholder URL, unused), `whitsun-proxy-worker/` | Abandoned — remove (and decommission the worker if deployed). |
| INC-02 | Landing / public home pages | `landing_page.dart` (7.5k lines), `public_home_page.dart` — not routed | Dead — archive or delete. |
| INC-03 | Dark mode | theme + branches, not wired | Partial. |
| INC-04 | Telemetry | `/api/analytics/telemetry` returns `{"status":"ok"}` without storing anything; client `TelemetryRouteObserver` posts to it | Stub — remove, or replace with Firebase Analytics (and disclose it). |
| INC-05 | Admin QR scanner (event check-in) | `admin_qr_scanner_page.dart` only reachable from admin pages (blocked on mobile) | Unreachable on the platform that has a camera. Decide whether event check-in should be a mobile staff feature. |
| INC-06 | AIS live vessels | depends on `AIS_API_KEY`; falls back to a static registry | Partial — label data source. |
| INC-07 | Market intelligence | static defaults unless admin edits | Partial. |
| INC-08 | SMS OTP | removed (comment in `auth.py`); login UI offers phone + password only | OK, but make sure no UI promises SMS codes. |
| INC-09 | Automated tests | placeholder widget test; backend tests need a live DB | Missing. |
| INC-10 | Report/block for messaging | absent | Missing (store-required). |
| INC-11 | Admin MFA | absent | Missing. |

## K. Recommended additional improvements

1. **Single source of truth for fees and bills.** Replace description-based fee matching with bill/fee IDs (SEC-20) — fewer payment disputes.
2. **Signed verification QR on certificates and member cards** that resolves to `/verify-member/<opaque-id>` (not the sequential DB ID), so third parties can check authenticity, and sequential IDs aren't exposed.
3. **Staging environment** (a second Supabase project plus a Fly app) so store reviewers and testers never touch production data.
4. **Error and crash monitoring** in both tiers (Sentry is already in the backend; add `sentry_flutter` or Crashlytics).
5. **Feature flags** for half-ready features (intelligence, vessels) so they can be hidden without a release.
6. **Accessibility pass** with TalkBack/VoiceOver on the 10 core screens.
7. **Internationalisation readiness** (`intl` is already a dependency): move strings to ARB files gradually; English-only is fine for v1.
8. **Ghana Data Protection Act, 2012 (Act 843):** confirm CUBAG's registration with the Data Protection Commission as a data controller, and name the controller in the privacy policy. (Legal confirmation required; not legal advice.)

---

## Appendix 1 — Endpoints without authentication (for review)

Public by design and acceptable (rate-limited where shown): `/auth/send-otp`, `/auth/verify-email`, `/auth/verify-otp`*, `/auth/resend-otp`, `/auth/register`, `/auth/login`, `/auth/forgot-password`, `/auth/reset-password`, `/complaints/submit`, `/complaints/track/<id>` (requires 128-bit secret), `/events/public*`, `/members/public/*`, `/members/verify/<id>`*, `/news/public/*`, `/news/blog`, `/news/global`, `/schedules/*`, `/intelligence/` (GET), `/payments/public/*`, `/payments/webhook` (HMAC), `/public/*` aliases, `/uploads/gallery/<file>`, `/api/vessels*`, health/ping.

\* no rate limit on the alias/route itself — add one.

**Must change:** `/members/<id>/certificate-pdf` (SEC-03), `/news/proxy-image` (SEC-05), `/compliance/payment-webhook` (SEC-19, fail-open), `/events/surveys/public/<id>/respond` (no rate limit), `/static/uploads/*` and `/uploads/*` for sensitive folders (SEC-04).

## Appendix 2 — What to verify outside the code (owner actions)

1. Supabase: RLS status and table grants (SEC-10); bucket public/private setting (SEC-04).
2. Secrets rotation status for everything listed in `render.yaml` (SEC-09); remove the token from `.git/config`.
3. Whether `cubag-whitsun-proxy` Worker is deployed (SEC-08).
4. Firebase project ownership (`schb-8cd66`) and APNs key upload.
5. WhitsunPay webhook URL and whether `WHITSUNPAY_WEBHOOK_SECRET` is set in Fly.
6. Which host is live (Fly vs Render), and delete the other.
7. Play developer account type (personal vs organisation) and Apple developer account type (organisation recommended; requires D-U-N-S).
8. The real Flutter/Xcode versions used to build (for target API 36 and iOS 26 SDK).
