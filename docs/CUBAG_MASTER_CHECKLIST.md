# CUBAG — Master Implementation Checklist

Status: `[ ]` Not started · `[~]` In progress · `[x]` Completed · `[!]` Blocked
Priority: **P0** must fix before release · **P1** production readiness · **P2** quality & experience · **P3** optional
IDs refer to `CUBAG_AUDIT_REPORT.md` (SEC/BUG/UI/RESP/DB/PERF/IOS/AND/INC). Phases match `CUBAG_IMPLEMENTATION_ROADMAP.md`.

_Last updated: 10 Nov 2026 (implementation session 1) — branch `release/p0-hardening`._

**Status rules used:** `[x]` = implemented **and** its automated tests ran and passed (backend: `python -m pytest tests_security`).
`[~]` = implemented but not yet verified end-to-end — all Flutter/iOS/Android changes are `[~]` until `flutter analyze`,
`flutter test` and a device build pass (no Flutter SDK was available in the implementation environment).
`[!]` = blocked on an owner action or decision (see `CUBAG_NEXT_STEPS.md`).

---

## Phase 0 — Owner verifications (no code; unblock everything else)

| Status | Pri | ID | Task | Owner |
|---|---|---|---|---|
| [ ] | P0 | SEC-10 | Check Supabase Security Advisor: is RLS disabled on `public` tables? Do `anon`/`authenticated` have grants? | Owner |
| [ ] | P0 | SEC-04 | Check whether the Supabase `uploads` bucket is public | Owner |
| [ ] | P0 | SEC-09 | Confirm every secret listed in `render.yaml` has been rotated since it was committed; if not, rotate (DB password, JWT/SECRET keys, Supabase service key, WhitsunPay keys + webhook secret, SMTP, AIS, Firebase SA) | Owner |
| [ ] | P0 | SEC-09 | Remove the token embedded in `CUSTOMS/.git/config` remote URL; revoke it on GitHub | Owner |
| [ ] | P0 | SEC-08 | Check Cloudflare: is the `cubag-whitsun-proxy` Worker deployed? If yes, delete it and rotate the WhitsunPay key | Owner |
| [ ] | P0 | SEC-09 | Confirm CUBAG owns Firebase project `schb-8cd66` (or create a CUBAG project) | Owner |
| [ ] | P0 | DB-07 | Decide the single production host (Fly vs Render); confirm the live webhook URL and that `WHITSUNPAY_WEBHOOK_SECRET` is set | Owner |
| [ ] | P0 | AND-03 | Decide the final Android application ID (recommend `com.cubag.app`) — irreversible after the first Play upload | Owner |
| [x] | P0 | IOS-07 | Decide how CTI **online** course fees are handled on iOS (hide / in-person only / IAP) | Owner |
| [ ] | P0 | IOS-05 | Decide messaging scope for v1: member↔member (needs report/block) or member↔Secretariat only | Owner |
| [ ] | P1 | 5.11 | Organisation developer accounts for Apple and Google (D-U-N-S) | Owner |
| [ ] | P1 | RESP-01 | Decide iPad support for v1 (recommend iPhone-only) | Owner |

## Phase 1 — Critical security fixes (backend)

| Status | Pri | ID | Task | File(s) | Test |
|---|---|---|---|---|---|
| [x] | P0 | SEC-01 | Restrict `GET /complaints` to admins with a `complaints` permission | `routes/complaints.py:463` | member → 403; admin → 200 |
| [x] | P0 | SEC-02 | Restrict `PUT /complaints/<id>/status`; audit-log changes | `routes/complaints.py:519` | member → 403 |
| [x] | P0 | SEC-03 | Certificate PDF: require auth, owner/admin only, active + good standing; remove licence auto-assignment on GET | `routes/members.py:1040` | anon 401; other member 403; pending 403; DB unchanged |
| [x] | P0 | SEC-05 | Delete `/news/proxy-image` or harden it like `/uploads/proxy` | `routes/news.py:353` | private IP / html URL → 403 |
| [~] | P0 | SEC-04 | Make the storage bucket private; store object paths; serve documents through an authenticated endpoint returning short-lived signed URLs; enforce auth in `serve_uploads` for sensitive folders | `file_storage.py`, `server.py:628-689`, upload routes, Flutter viewers | anon → 401; owner → 200; signed URL expires |
| [x] | P0 | SEC-04 | Migrate existing document URLs in DB to object paths | DB script | spot-check 10 records |
| [!] | P0 | SEC-04 | Remove `cubag-backend/uploads/**` from git and purge history (`git filter-repo`) | repo | `git ls-files uploads` empty |
| [~] | P0 | SEC-10 | Enable RLS on all `public` tables (no policies) and revoke `anon`/`authenticated` grants | SQL migration | REST call with anon key returns nothing |
| [x] | P0 | SEC-07 | Block `deleted`/`rejected` in login and `enforce_account_status`; make deletion clear credentials and identifiers, and remove documents | `routes/auth.py:388-445, 1594`, `server.py:321` | delete → login by licence number fails; old token → 401/403 |
| [x] | P0 | SEC-06 | Permission checks on GDPR routes and compliance settings | `routes/gdpr.py`, `routes/compliance_settings.py` | sub-admin(events) → 403 |
| [x] | P0 | SEC-19 | Compliance webhook: fail closed + timestamp check (reuse payments implementation) | `routes/compliance.py:1775` | unsigned → 401 |
| [x] | P0 | BUG-02 | Return 401 (not 503) for expired/invalid JWT in `enforce_account_status` | `server.py:321-373` | expired token → 401 |
| [ ] | P1 | SEC-12 | Admin MFA (email-OTP or TOTP step-up) | `routes/auth.py`, admin web login | admin login requires second factor |
| [x] | P1 | SEC-16 | `token_version` column; bump on password change/reset/deletion; check per request | `auth.py`, `server.py` | old token rejected after reset |
| [~] | P1 | SEC-15 | Email change requires OTP to the new address; notify the old one | `routes/auth.py:1318` | change without OTP → 400 |
| [x] | P1 | SEC-17 | Trust only the active platform's client-IP header; per-account login failure counter | `config/rate_limit.py`, `auth.py` | spoofed header doesn't reset limit |
| [x] | P1 | SEC-18 | Replace `str(e)` responses with generic messages + correlation ID (≈50 sites + global handler) | `routes/*.py`, `server.py:791` | forced error shows no internals |
| [ ] | P1 | SEC-20 | Pay by `bill_id`/`fee_id` (server-derived amount); reject unmatched descriptions | `routes/payments.py`, `config/payment_validation.py` | tampered amount rejected |
| [!] | P1 | SEC-09 | Send email from a CUBAG domain with SPF/DKIM/DMARC | env + DNS | mail-tester score ≥ 9 |
| [~] | P2 | SEC-21 | Set Content-Type from extension; magic-byte check | `file_storage.py`, upload routes | `.png` containing HTML rejected |
| [ ] | P2 | SEC-22 | Restrict CORS/Socket.IO origins to real web origins | `server.py:201`, `socket_instance.py` | foreign origin blocked (web) |
| [ ] | P2 | SEC-23 | Admin re-confirms fee category/scale at approval | admin members flow | — |
| [ ] | P2 | SEC-24 | Mask phone/account numbers in logs | `routes/payments.py` | log review |
| [x] | P2 | BUG-12 | Messaging: validate recipient, max length, rate limit | `routes/messages.py` | 2,001-char message → 400 |
| [~] | P2 | — | Add rate limits to `/auth/verify-otp` alias, `/members/verify/<id>`, public survey respond | routes | 429 after limit |

## Phase 2 — Mobile security & store blockers (Flutter + native config)

| Status | Pri | ID | Task | File(s) | Test |
|---|---|---|---|---|---|
| [~] | P0 | SEC-11 | Remove "Configure Server Connection" dialog from release builds; ignore `custom_api_url` in release | `login_page.dart:92-260, 623-640`, `api_service.dart:18-27` | release build: no link on network error |
| [~] | P0 | BUG-03 | Release keystore + `key.properties` (git-ignored, backed up); fail build without it; Play App Signing | `android/app/build.gradle.kts` | `apksigner verify` shows upload cert |
| [!] | P0 | AND-03 | Apply final application ID (if changing) + new `google-services.json` | Android project | FCM works on new ID |
| [~] | P0 | AND-01 | Ensure `targetSdk = 36` | `build.gradle.kts` / Flutter version | merged manifest shows 36 |
| [!] | P0 | IOS-01 | Build with Xcode 26 / iOS 26 SDK | CI/local | App Store Connect accepts upload |
| [~] | P0 | BUG-01 / IOS-02 | Link entitlements (Debug/Release), add Push + Remote-notification capability, upload APNs key to Firebase | Xcode project | TestFlight device receives push |
| [~] | P0 | IOS-03 | Remove `NSAllowsArbitraryLoads`, `NSAllowsLocalNetworking`, `NSLocalNetworkUsageDescription` | `ios/Runner/Info.plist` | app works on HTTPS only |
| [~] | P0 | IOS-10 | Remove `fetch` and `processing` background modes | `Info.plist` | no upload warnings |
| [!] | P0 | IOS-11 / AND-08 | Remove camera permission + `mobile_scanner` from mobile (or expose staff check-in) | `AndroidManifest.xml`, `Info.plist`, `pubspec.yaml` | permission absent in build |
| [~] | P0 | IOS-05 / AND-05 | Messaging: report message/user, block user, admin moderation queue (or restrict to Secretariat) | `messaging_page.dart`, `routes/messages.py` | blocked user can't message |
| [~] | P0 | IOS-07 | Implement the CTI online-course payment decision on iOS | `cti_courses_page.dart`, `guest_service_request_page.dart` | iOS build has no MoMo pay for online courses (if chosen) |
| [~] | P1 | SEC-13 | Stop writing `cubag_token` to SharedPreferences; delete legacy copy | `session_storage_stub.dart` | prefs file has no token |
| [ ] | P1 | SEC-14 | Biometric: store a revocable device token instead of the password (backend support needed) | `biometric_service_native.dart`, `auth.py` | password not in keychain |
| [ ] | P1 | PERF-08 | Encrypt the Hive `api_cache` box, or exclude sensitive endpoints | `api_service.dart`, `main.dart` | box file unreadable |
| [ ] | P1 | BUG-04 | Add Crashlytics or `sentry_flutter`; route `FlutterError`/`PlatformDispatcher` errors to it | `main.dart` | test crash appears in console |
| [~] | P1 | BUG-07 | Request notification permission after login with an explainer | `main.dart`, `push_notification_service.dart` | fresh install: no prompt before login |
| [~] | P1 | IOS-14 | Add app-level `PrivacyInfo.xcprivacy` | `ios/Runner/` | Xcode privacy report clean |
| [ ] | P1 | AND-07 | Verify 16 KB page-size compatibility; update plugins if needed | build output | Play pre-launch report passes |
| [ ] | P1 | AND-06 | Edge-to-edge check on Android 15/16 | all screens | no content under system bars |
| [~] | P1 | RESP-02 | Lock phones to portrait (unless landscape is intended) | `main.dart`, `Info.plist` | rotation has no effect |
| [!] | P1 | RESP-01 | Apply the iPad decision (iPhone-only, or fix tablet layouts) | Xcode `TARGETED_DEVICE_FAMILY` | — |

## Phase 3 — Compliance content & store listing

| Status | Pri | ID | Task | Test |
|---|---|---|---|---|
| [ ] | P0 | IOS-09 / 3.2 | Rewrite privacy policy (accurate security claims, processors, retention, deletion, controller, Act 843) — legal review | lawyer sign-off |
| [ ] | P0 | 3.1 | Publish privacy policy + terms at public URLs; link from Settings and the stores | URLs load without login |
| [ ] | P0 | 3.4 | Publish web account-deletion request page | form submits; Secretariat receives |
| [ ] | P0 | AND-04 / 3.6 | Complete Play Data safety and Apple App Privacy from the data inventory | consoles show complete |
| [ ] | P0 | IOS-06 / 5.2 | Create the fully active reviewer demo account with sample data; write review notes | log in as reviewer on a clean device |
| [ ] | P0 | AND-09 / IOS-16 | Content rating questionnaire (Play) and age rating (Apple) | ratings issued |
| [ ] | P1 | UI-08 | New high-resolution square logo master; adaptive Android icon; regenerate icons and splash | icon is sharp at 1024 px |
| [ ] | P1 | AND-10 / 2.4 | Screenshots (iPhone 6.9", iPad 13" if enabled, Play phone + feature graphic) | consoles accept |
| [x] | P1 | BUG-10 / IOS-15 | Label or hide static vessel/intelligence data | reviewer can't mistake it for live |
| [x] | P1 | BUG-11 | Remove invented fallbacks on certificates/verification; signatories and years from settings | pending member → no certificate |

## Phase 4 — Functional hardening & testing

| Status | Pri | ID | Task | Test |
|---|---|---|---|---|
| [!] | P1 | BUG-06 | Un-ignore `.github/`, pin Flutter/Python versions matching real builds, make CI green | CI runs on PR |
| [ ] | P1 | INC-09 | Backend tests for every SEC fix (authorisation matrix: anon/member/sub-admin(no perm)/sub-admin(perm)/admin) against a disposable Postgres | tests pass in CI |
| [ ] | P1 | INC-09 | Flutter: router redirect tests (exist), login/registration widget tests, API error-mapping tests | tests pass in CI |
| [ ] | P1 | — | Manual smoke test on 4–5 devices: register → OTP → documents → pay → approval → dashboard → renew → message → delete account | test log signed off |
| [ ] | P1 | BUG-09 / PERF-07 | Move rating recalculation off read paths | `GET /members/<id>` performs no writes |
| [ ] | P2 | BUG-13 | Ownership check before storing compliance uploads | non-owner upload leaves no file |
| [ ] | P2 | BUG-08 | No writes on GET anywhere (search for UPDATE in GET handlers) | code review |

## Phase 5 — Database & backend operations

| Status | Pri | ID | Task | Test |
|---|---|---|---|---|
| [ ] | P1 | DB-01 | Export current schema → versioned migrations; remove runtime DDL from request handlers | fresh DB builds from migrations |
| [ ] | P1 | DB-03 | Index review from Supabase query stats; add `LOWER(email)` and normalised phone | p95 of login/payments < 300 ms |
| [ ] | P1 | DB-05 | Use the Supabase pooler; pool max ≈ 10–12 | no connection-limit errors under load test |
| [ ] | P1 | DB-07 | Delete the unused deployment config; prune CSP/allow-lists | — |
| [ ] | P2 | DB-04 | Member status enum/check constraint + single helper | — |
| [ ] | P2 | DB-06 | Redis (e.g. Upstash) for cache and rate limits | limits survive deploy |
| [ ] | P2 | DB-08 | Deletion removes storage objects; retention job documented | deleted member has no files |
| [ ] | P2 | PERF-10 | `Cache-Control: max-age` on public GETs | headers present |
| [ ] | P3 | DB-09 | Verify the webhook URL registered with WhitsunPay | test webhook arrives |

## Phase 6 — UI/UX, accessibility & responsiveness

| Status | Pri | ID | Task | Test |
|---|---|---|---|---|
| [ ] | P1 | UI-02 | Contrast-safe orange for text (≈`#C2410C`), darker muted text (≈`#64748B`) | all text ≥ 4.5:1 |
| [ ] | P1 | UI-03 | Tooltips/semantic labels on icon buttons and tappable cards (core 10 screens first) | TalkBack/VoiceOver walkthrough |
| [ ] | P1 | RESP-03 | Keyboard-safe bottom sheets/dialogs with text fields | iPhone SE: no field hidden by keyboard |
| [ ] | P1 | RESP-05 | Safe-area check on screens without AppBar | notch/punch-hole devices |
| [ ] | P2 | UI-01 | Design tokens via `ThemeExtension` (colours, radius, spacing, type scale); migrate pages as touched | new code uses tokens only |
| [ ] | P2 | UI-04 | Raise text-scale cap to ≥1.3, fix overflows; target 2.0 | 200% system font usable |
| [ ] | P2 | UI-06 / PERF-03 | Bundle fonts properly; disable runtime font fetching in release | airplane-mode first launch uses Inter |
| [ ] | P2 | RESP-04 | Flexible dashboard grids | large text: no clipping |
| [ ] | P2 | UI-09 | One error view + status-code message mapping | consistent errors |
| [ ] | P2 | UI-12 | Split payments page into tabs/steps | — |
| [ ] | P2 | PERF-05 | `CachedNetworkImage` everywhere; compress uploads client-side | upload ≤ 1.5 MB |
| [ ] | P2 | PERF-06 | Lazy lists/pagination for payments, notifications, messages, directory | smooth scroll with 500 items |
| [ ] | P2 | UI-11 | Admin-on-mobile screen: link/QR to web portal | — |
| [ ] | P3 | UI-05 | Radius scale | — |
| [ ] | P3 | UI-07 / INC-03 | Finish or remove dark mode | — |
| [ ] | P3 | UI-10 | One skeleton loader style | — |
| [ ] | P3 | UI-13 | Plain-language copy pass | — |
| [ ] | P3 | UI-14 | Limit `SelectionArea` to copyable content | — |

## Phase 7 — Cleanup & optional

| Status | Pri | ID | Task |
|---|---|---|---|
| [ ] | P2 | INC-01 | Remove `whitsun_pay_service.dart` and `whitsun-proxy-worker/` |
| [ ] | P2 | INC-02 | Archive `landing_page.dart`, `public_home_page.dart` |
| [ ] | P2 | INC-04 | Remove the telemetry stub or replace it with Firebase Analytics (disclosed) |
| [ ] | P3 | PERF-02 | Remove the Render wake-up ping |
| [ ] | P3 | PERF-11 | Enable R8 shrinking |
| [ ] | P3 | K-2 | Signed verification QR on certificates/cards with opaque IDs |
| [ ] | P3 | K-3 | Staging environment |
| [ ] | P3 | K-7 | Move strings to ARB files |

---

### Progress summary

| Phase | P0 | P1 | P2 | P3 | Done |
|---|---|---|---|---|---|
| 0 Owner verifications | 10 | 2 | 0 | 0 | 0 |
| 1 Backend security | 12 | 7 | 6 | 0 | 0 |
| 2 Mobile & store blockers | 11 | 10 | 0 | 0 | 0 |
| 3 Compliance & listing | 6 | 4 | 0 | 0 | 0 |
| 4 Functional & testing | 0 | 5 | 2 | 0 | 0 |
| 5 DB & ops | 0 | 4 | 4 | 1 | 0 |
| 6 UI/UX & responsive | 0 | 4 | 9 | 5 | 0 |
| 7 Cleanup | 0 | 0 | 3 | 5 | 0 |
