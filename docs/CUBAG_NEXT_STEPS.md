# CUBAG — Implementation Checkpoint & Next Steps

_Checkpoint written 10 Nov 2026 at the end of implementation session 1; updated same day (verification batch) with reconciled test counts and a fixture fix. Resume from here; don't redo completed items._

## ⚠ Action needed: rotate the secrets you pasted into this chat

You pasted the real `cubag-backend/.env` file (with live `DB_PASSWORD`, `DATABASE_URL`, `SECRET_KEY`, `JWT_SECRET_KEY`, `SMTP_PASS`, `RESEND_API_KEY`, `WHITSUNPAY_API_KEY` (`wp_live_...`), `WHITSUNPAY_WEBHOOK_SECRET`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`, `AIS_API_KEY`, and the full Firebase service-account private key) directly into the conversation. None of those values were used, logged, or sent anywhere by me — I never need them for this work and never connect to your production services — but once a secret has been typed into a chat it should be treated as potentially exposed. Please rotate **all** of the above (new DB password, new Supabase service/anon keys via Supabase dashboard, new JWT/Flask secret keys, new SMTP app password, new Resend key, new WhitsunPay API key + webhook secret, and a new Firebase service-account key with the old one revoked in the Firebase/GCP console) — this is the same rotation already listed as owner action #3 below, now more urgent.

## Session 2 status (10 Nov 2026, ~16:15 PST) — read this first

Full evidence: `docs/CUBAG_VERIFICATION_LOG.md`. Device test sheet: `docs/CUBAG_DEVICE_TEST_CHECKLIST.md`.

| Phase of the second directive | Status |
|---|---|
| 1 Second verification run | **Blocked on the owner**: `verify_cubag.command` has not been run since `a8b41f8`. Backend fake-DB suite re-run: 75 passed. Flutter analyze/tests, iOS build and the Android debug build are **not** re-verified. |
| 2 Android release signing | Reviewed (below). Configuration is correct; `android/key.properties` and a keystore do not exist — owner action. |
| 3 Real PostgreSQL | Done on a local PostgreSQL 16: new `tests_pg/` 21 passed; legacy `tests/` 9–10 pre-existing failures; 3 real bugs found and fixed (`da03dd5`). |
| 4 Device verification | Checklist written. **Nothing tested on a simulator or device.** |
| 5 SEC-14 | **Not started** — held until phase 1 completes, as instructed. |
| 6 Docs | Updated. |

Commits this session: `b191564` test fixture · `12bab57` docs · `a8b41f8` debug manifest + analyzer infos · `da03dd5` delete-account / fresh-DB fixes · `e88b117` `tests_pg` + legacy guard · `71546e0` note · docs commit after this one.

### Android release signing (phase 2)

- `android/app/build.gradle.kts` reads `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) into a `release` signing config. Release builds use it only when the file exists; otherwise any `assemble/bundle/package…Release` task stops with "Release signing is not configured". There is no fallback to the debug key. Debug builds use the default debug key and are unaffected.
- `key.properties`: **does not exist**. Keystore (`*.jks` / `*.keystore`): **none in the project**. Neither has ever been committed (checked `git ls-files` and `git log --all`).
- `android/.gitignore` already ignores `key.properties`, `**/*.keystore`, `**/*.jks`.
- Run 1 confirmed the guard fires. A signed release build has never been produced.

To create the upload key (do this yourself; I must not generate or hold production signing credentials):

```bash
keytool -genkey -v -keystore ~/cubag-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `cubag_flutter/android/key.properties` (never commit it):

```properties
storePassword=<the password you chose>
keyPassword=<the password you chose>
keyAlias=upload
storeFile=/Users/guyman-gh/cubag-upload-keystore.jks
```

Back up the keystore and passwords somewhere safe outside the repo, enrol in Play App Signing when you create the app in Play Console, then run `flutter build appbundle --release`. Decide the application ID (`com.cubag_flutter` vs `com.cubag.app`) **before** the first upload — iOS already uses `com.cubag.app`.

### Running the real-PostgreSQL suite on your Mac

Needs a local PostgreSQL (e.g. `brew install postgresql@16 && brew services start postgresql@16`). It refuses anything that is not a local server and a database named `*_test`.

```bash
createdb cubag_test
cd ~/Downloads/CUB-26/CUSTOMS/cubag-backend
TEST_DATABASE_URL="host=127.0.0.1 port=5432 dbname=cubag_test" ./venv/bin/python -m pytest tests_pg -q
```

This matters because my run used a test-only driver adapter in place of `psycopg2` (see the verification log).

### Open findings from this session

1. `complaints` and `cti_course_enrollments` are used by the code but created nowhere in the repository (DB-01). Needed from you: `pg_dump --schema-only` of production (schema only, no data) so real definitions can be put in migrations.
2. Legacy `tests/`: payment state machine allows `failed → paid`; a legacy test says it must not. Decision needed.
3. Legacy `tests/`: 8 tests are out of date with behaviour that predates this branch (CSRF 403 before 401; webhook timestamp header). Not changed.
4. `otp_codes.code` stores verification codes in plain text (pre-existing). Not changed; candidate for hashing.
5. The messaging report queue has API endpoints but no admin screen yet.
6. `cubag-backend/routes/front-page.php`: untracked, never in git history, created 10 Nov 13:31 PST, 3,708 bytes, SHA-256 `3260c7ad…13c4`. It is a WordPress template that shows member statistics from the public `/api/v1/public/stats` endpoint. It contains no `eval`, shell, upload or request-input code, nothing in the project references it, and Flask does not serve or execute PHP. Not created by me; left untouched. It looks like a website snippet saved into the wrong folder — only you can confirm where it came from.

## Where things stand (session 1 detail)

| | |
|---|---|
| Branch | `release/p0-hardening` (created from `main` @ `ebc211d`) |
| Commits | (see `git log release/p0-hardening`) `f3ff2b2` security batch 1 · `4a9374c` CTI course policy (backend) · `483ed2f` mobile store blockers + CTI UI · `6884696` SEC-04/SEC-10/SEC-21 · `2ed89e5` messaging report/block · `125173a` docs checkpoint · `aee1419` BUG-10/11 + test isolation · `b191564` SEC-04 test fixture fix (this session) |
| Pushed? | **No.** Local branch only. Nothing deployed. |
| Backend tests | `cd cubag-backend && python -m pytest tests_security -q` → **75 collected, 75 passed, 0 errors** (reconciled and re-run this session; see breakdown below). |
| Flutter | **Not compiled or tested here** — no Flutter SDK in this workspace. `verify_cubag.command` is sitting in `CUSTOMS/` for you to double-click; see "Verify first" below. Not run yet as of this checkpoint. |
| Legacy backend tests (`tests/`) | Run in session 2 against a local PostgreSQL 16 only — see "Session 2 status" above and the verification log. |

### Backend test count, reconciled

An earlier checkpoint said "75 passed" without listing every file, which didn't add up against the 4 files it named. Exact collected counts, per file, confirmed via `pytest tests_security --collect-only -q`:

| File | Tests | Covers |
|---|---|---|
| `test_batch1_authz.py` | 35 | SEC-01/02/03/05/06/07/15/16/17/18/19, BUG-02 |
| `test_cti_course_payments.py` | 19 | CTI online/hybrid iOS payment block (directive §3) |
| `test_sec04_private_documents.py` | 11 | Signed URLs, access control on sensitive docs |
| `test_messaging_safety.py` | 7 | Block/report |
| `test_bug10_11_no_fake_data.py` | 3 | BUG-10 (AIS not presented as live), BUG-11 (no invented licence/verification data) |
| **Total** | **75** | |

The earlier "72 vs 75" discrepancy was simply that the checkpoint's file list omitted `test_bug10_11_no_fake_data.py` (3 tests) — nothing was miscounted or fabricated, just under-listed.

**All 75 are fake-DB unit tests** (`tests_security/`, using `fakedb.py`'s in-memory stand-in for `psycopg2` — no real Postgres, no network). They verify request/response behaviour, authorization logic and payload shape, not real SQL correctness, real constraint behaviour, or real Supabase RLS. Real-PostgreSQL coverage is separate: `tests_pg/` (added in session 2, 21 tests) and the legacy `tests/` directory; results are in `CUBAG_VERIFICATION_LOG.md`.

**Fixture bug found and fixed during this reconciliation pass:** a re-run surfaced `75 passed, 4 errors` — `PermissionError` in `test_sec04_private_documents.py`'s `local_receipt` fixture, which was writing/deleting a file directly inside the real `cubag-backend/uploads/receipts/` folder. Rewrote it to use pytest's `tmp_path` + `monkeypatch.chdir()` so it never touches that real folder. Re-ran: clean `75 passed`, confirmed no stray files left behind. Committed as `b191564` on `release/p0-hardening`.

## Completed (with evidence)

Backend — implemented **and** covered by passing tests in `cubag-backend/tests_security/`:

| ID | What changed | Main files |
|---|---|---|
| SEC-01/02 | Complaints list/update require `complaints` permission; updates audit-logged | `routes/complaints.py` |
| SEC-03 | Certificate PDF: auth, owner/admin, active + good standing, no DB writes, no invented licence number | `routes/members.py` |
| SEC-05 | `news/proxy-image` delegates to hardened authenticated proxy | `routes/news.py` |
| SEC-06 | GDPR routes need `gdpr`; fee settings PUT needs `fees` | `routes/gdpr.py`, `routes/compliance_settings.py`, `routes/sub_admins.py` |
| SEC-07 | Deleted accounts can't log in (any identifier) or use tokens; deletion nulls password/IDs, purges personal rows | `routes/auth.py`, `server.py`, `config/authz.py` |
| BUG-02 | Expired/invalid token no longer returns 503 | `server.py` |
| SEC-15 | Email change needs a code sent to the new address (202 → resubmit with `email_otp`) | `routes/auth.py` |
| SEC-16 | `members.token_version` (+ `tv` claim); bumped on password change/reset/deletion; change-password returns a fresh token; wrong current password is 400 not 401 | `routes/auth.py`, `server.py`, `config/db.py` |
| SEC-17 | Per-account login lockout (10 fails / 15 min); only the configured client-IP header is trusted (`CLIENT_IP_HEADER`, default `Fly-Client-IP`) | `routes/auth.py`, `config/rate_limit.py` |
| SEC-18 | All 5xx JSON bodies scrubbed centrally (+ `error_id`); decorator no longer returns tracebacks | `server.py`, `utils.py` |
| SEC-19 | Compliance webhook fails closed, has replay window; **also exempted from CSRF — it was being rejected with 403 before** | `routes/compliance.py`, `config/csrf.py` |
| SEC-04 (code) | `GET /uploads/sign` signed URLs (owner/admin only); sensitive local files enforced; works before/after bucket goes private; optional `SUPABASE_PUBLIC_BUCKET` | `config/file_access.py`, `routes/uploads.py`, `server.py`, `file_storage.py` |
| CTI policy | iOS (`X-Client-Platform: ios`) cannot start payment for online/hybrid courses (member, bank slip, guest MoMo); in-person, Android, web, dues/registration/renewal unaffected; course lists carry `delivery_mode` + `in_app_payment_available`; neutral message, no steering. Also fixed course fee lookup for `CTI Course: <title>` descriptions. | `config/course_payment_policy.py`, `routes/payments.py`, `routes/events_surveys.py`, `config/payment_validation.py` |
| UGC / BUG-12 | Block/unblock/report endpoints, admin report queue, sends refused to blocked/deleted members, 2,000-char cap, rate limit | `routes/messages.py` |

Test files: `test_batch1_authz.py` (35), `test_cti_course_payments.py` (19, covers directive §3.4 items 4–9 at the API level), `test_sec04_private_documents.py` (11), `test_messaging_safety.py` (7).

## Implemented but NOT yet verified (`[~]`)

All Flutter / native changes. They were syntax-checked for bracket balance only.

| ID | Change | Files |
|---|---|---|
| CTI policy (UI) | Delivery-mode badges, "Pay in app" badge, iOS online/hybrid shows status only (no button/form/link); guest page submits request without payment | `lib/utils/course_payment_policy.dart`, `lib/utils/platform_info.dart`, `pages/cti_courses_page.dart`, `pages/guest_service_request_page.dart`; test `test/course_payment_policy_test.dart` |
| — | `X-Client-Platform` header on every request (backend CORS allows it) | `services/api_service.dart`, `server.py` |
| SEC-11 | Server-config dialog + custom API URL only in debug builds | `pages/login_page.dart`, `services/api_service.dart` |
| SEC-13 | Token only in secure storage; legacy plaintext copy migrated/removed | `utils/session_storage_stub.dart` |
| SEC-25 (new finding) | Android PDF viewer no longer sends token-bearing URLs to Google Docs viewer; renders with `printing` | `components/in_app_document_viewer.dart` |
| SEC-04 (app) | Documents/receipts opened via signed URLs | `services/api_service.dart`, `components/cors_image_widget.dart`, `components/in_app_document_viewer.dart`, admin compliance/documents/members pages |
| SEC-15/16 (app) | Email-change code prompt; fresh token saved after password change | `pages/profile_page.dart`, `pages/settings_page.dart`, `pages/admin_settings_page.dart` |
| UGC (app) | "Report member" / "Block member" in chat header | `pages/messaging_page.dart` |
| BUG-07 | No notification prompt at cold start (asked after login) | `services/push_notification_service.dart` |
| RESP-02 | Phones locked to portrait (tablets rotate); iPhone portrait in Info.plist | `lib/main.dart`, `ios/Runner/Info.plist` |
| BUG-01/IOS-02 | Entitlements linked for Debug/Release/Profile | `ios/Runner.xcodeproj/project.pbxproj` |
| IOS-03/10 | ATS exceptions, local-network string, `fetch`/`processing` modes removed | `ios/Runner/Info.plist` |
| IOS-14 | App-level privacy manifest added to the Runner target | `ios/Runner/PrivacyInfo.xcprivacy`, `project.pbxproj` |
| AND-01 | `compileSdk`/`targetSdk` ≥ 36 | `android/app/build.gradle.kts` |
| BUG-03 | Release build fails without `key.properties` (no more debug-signed releases) | `android/app/build.gradle.kts` |

## Verification run 1 — results (10 Nov 2026, 15:40–15:44 PST, `verify_cubag.command`, Flutter 3.44.8 / Dart 3.12.2)

Logs: `docs/verify_logs/` (untracked).

| Step | Result | Notes |
|---|---|---|
| `flutter pub get` | pass | |
| `flutter analyze` | pass, 0 errors, 0 warnings, 3 infos | 2 deprecated `Radio` params in the new report dialog, 1 style hint in the new test |
| `flutter test` | **84 passed, 0 failed** | includes `course_payment_policy_test.dart` |
| `flutter build apk --debug` | **FAILED** | manifest merger: `usesCleartextTraffic` true (debug manifest) vs false (main). Pre-existing conflict, not from this branch's changes |
| `flutter build appbundle --release` | failed as designed | "Release signing is not configured" — the BUG-03 guard. Needs `android/key.properties` (owner) |
| `pod install` | pass | CocoaPods base-configuration warning for the Profile config; Firebase CocoaPods deprecation notice |
| `flutter build ios --release --no-codesign` | **pass** | `Runner.app` 38.1 MB, bundle id `com.cubag.app`; entitlements + privacy manifest compile |
| backend `pytest tests_security` (on macOS, real venv) | **75 passed** | |

Fixes made after run 1 (commit follows this checkpoint) — **not yet re-verified, run `verify_cubag.command` again**:
- `android/app/src/debug/AndroidManifest.xml`: `tools:replace="android:usesCleartextTraffic"` so the debug APK builds.
- `lib/pages/messaging_page.dart`: report dialog uses `RadioGroup` (clears the 2 deprecation infos).
- `test/course_payment_policy_test.dart`: null-aware map element (clears the style info).

Still unverified at any level: an Android build of any kind (so `targetSdk 36` is unconfirmed in a merged manifest), and every on-device behaviour — CTI payment UI on iOS/Android, email-change OTP dialog, secure token storage and sign-out after password change, signed-URL document viewing, messaging report/block. These need a simulator/device pass; the mobile rows stay `[~]` until then.

## Verify first (on your Mac, before anything else) — run 2 needed

I can't run Flutter/Xcode/Gradle myself (no SDK in this cloud workspace, and I deliberately did not try to drive this through screen/Terminal automation — that would have required typing into Terminal, which the access I was granted explicitly disallows, as a safeguard against an agent running arbitrary shell commands that way).

A ready-to-run script is already sitting at `CUSTOMS/verify_cubag.command` (executable). **Please double-click it in Finder** (or right-click → Open if Gatekeeper blocks it the first time). It:

1. Runs `flutter pub get`, `flutter analyze`, `flutter test`.
2. Builds `flutter build apk --debug` and `flutter build appbundle --release` (the release build is **expected to fail** until `android/key.properties` exists — that's BUG-03 working as intended, not a bug).
3. Runs `pod install` and `flutter build ios --release --no-codesign`.
4. Runs the backend `pytest tests_security -q` for a final cross-check.
5. Logs everything to `docs/verify_logs/*.log` plus a `docs/verify_logs/summary.txt`.

It does not read `.env`, does not touch any server, and takes roughly 10–20 minutes. Run 1 is recorded above. Run it once more to confirm the three post-run fixes (debug APK should now build; analyze should report 0 issues).

Then the manual iOS check for the CTI policy (directive §3.4 items 1–3 visually): on an iPhone, open CTI Courses → an Online and a Hybrid course show details, a mode badge and "Not enrolled"/"Enrolled" with **no** payment button; an In-person course shows "Enroll Now" and "Pay in app" and opens the payment screen. Repeat on Android: all three can be paid. Same for the email-change OTP flow, secure token storage + forced logout after password change, signed-URL document viewing, and messaging report/block — all are backend-tested (see table above) but not yet exercised through the actual Flutter UI.

## Owner actions / decisions still required (`[!]`)

1. **Supabase (SEC-10):** run `cubag-backend/migrations/2026_11_10_sec10_lockdown_supabase_rest.sql` after a backup (instructions inside). Not run by me — no credentials, and it changes production permissions.
2. **Supabase bucket (SEC-04):** follow `cubag-backend/migrations/2026_11_10_sec04_private_bucket.md` **after** deploying this backend and shipping the app.
3. **Secrets (SEC-09):** confirm/rotate everything listed in `render.yaml`; remove the token from `CUSTOMS/.git/config`; send email from a CUBAG domain.
4. **WhitsunPay Worker (SEC-08):** check whether `cubag-whitsun-proxy` is deployed; if so delete it and rotate the key.
5. **Android application ID (AND-03):** has `com.cubag_flutter` ever been uploaded to Play? If not, decide whether to change to `com.cubag.app` before the first upload.
6. **Release keystore (BUG-03):** create `android/key.properties` + upload keystore (keep out of git, back up).
7. **APNs key (BUG-01):** upload the APNs auth key to Firebase project `schb-8cd66` (and confirm CUBAG owns that project).
8. **Camera permission (IOS-11/AND-08):** the QR scanner is admin-only and admins are web-only. Keep `mobile_scanner` (needed by the web admin scanner, so the iOS camera string must stay) or expose event check-in to staff on mobile.
9. **iPad (RESP-01):** keep iPad support (needs tablet layout work + iPad screenshots) or ship iPhone-only for v1.
10. **Git history purge (SEC-04):** personal documents under `cubag-backend/uploads/` are in git history; purging needs `git filter-repo` + force-push — requires your approval.
11. **Deploy settings:** on Render (if still used) set `CLIENT_IP_HEADER=X-Forwarded-For`; keep `WHITSUNPAY_WEBHOOK_SECRET` set (compliance webhook now refuses unsigned calls).

## Behaviour changes to tell admins/members about

- Sub-admins need the new `complaints`, `gdpr` or `fees` permission (Admin → Sub-admins).
- After a password change/reset, all other devices are signed out.
- Email changes now require a code sent to the new address.
- Certificates are only issued to active members in good standing with an issued licence number.
- Course fee charged for `CTI Course: <title>` payments is now that course's own fee (previously could fall back to a generic CTI fee).

## Exact next tasks (in order)

1. Fix anything `flutter analyze`/`flutter test` reports in the files above; then mark those rows `[x]`.
2. **SEC-14** biometric: replace stored password with a revocable device token (`POST /auth/biometric-token`, stored hashed; revoke on logout/password change/deletion).
3. **PERF-08** encrypt the Hive `api_cache` box (`HiveAesCipher`, key in secure storage).
4. **BUG-04** crash reporting (Crashlytics or `sentry_flutter`) — adds a dependency; confirm choice.
5. **BUG-10 (rest)**: `/api/vessels` no longer serves the AIS *simulation* as live, and the static registry no longer carries stale ETAs (done, tested). Still to do: label the default market-intelligence data (`data/intelligence.json`) in the app, and make the vessel screen show an empty state when `live` is false.
6. ~~BUG-11~~ done (certificate + public verification no longer invent numbers/dates).
7. **SEC-12** admin MFA (email OTP step-up on web admin login).
8. **SEC-20** pay by fee/bill id instead of free-text description.
9. **BUG-06** CI — blocked for me: `.github/workflows/ci.yml` is a protected file that remote tools can't write. A ready-to-use workflow is in `docs/ci.yml.proposed`: copy it to `.github/workflows/ci.yml`, remove the `.github/` line from the root `.gitignore`, and pin the Flutter version you build with.
10. Store docs: privacy policy rewrite (legal review), public URLs, Data safety / App Privacy answers (use `PrivacyInfo.xcprivacy` + `CUBAG_STORE_READINESS.md` §6), reviewer demo account.
11. Phase 5–6 (DB migrations/indexes, UI/UX token pass) per roadmap.

## Test-safety note

`tests_security/conftest.py` blanks every outbound integration (email, MoMo,
Supabase, Firebase, AIS) before the app loads, because the app calls
`load_dotenv()` and your local `cubag-backend/.env` contains live credentials.
Earlier runs in this session loaded that `.env` before the blanking was added;
the workspace had no route to those services (checked: Resend, WhitsunPay,
FCM and Supabase were all unreachable), so no email, MoMo prompt or push was sent.

## How tests are run here (for the next session)

The workspace on your Mac (Linux VM) has no PyPI access, so backend dependencies are copied from your existing `cubag-backend/venv` (pure-Python packages only) into `~/pylib` inside that VM:

```bash
cd ~/mnt/CUB-26/CUSTOMS/cubag-backend
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$HOME/pylib python3 -m pytest tests_security -q -p no:cacheprovider
```

`tests_security/` replaces `psycopg2` with an in-memory fake (`fakedb.py`), so tests never touch a real database or network.
