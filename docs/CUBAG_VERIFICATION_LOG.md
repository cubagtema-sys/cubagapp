# CUBAG — Verification Log

Evidence only: what was run, where, and what came back. Newest entry last.
Branch `release/p0-hardening`. Nothing here was run against production.

Evidence levels used in this project:

| Level | Meaning |
|---|---|
| Fake-DB unit | `tests_security/` — app code with an in-memory stand-in for PostgreSQL |
| Real PostgreSQL | `tests_pg/` — app code against a real local PostgreSQL server |
| Flutter unit | `flutter test` — Dart logic, no device |
| Build | compiles/links for the platform; says nothing about runtime behaviour |
| Simulator / Physical device | a person exercised the screen |

---

## Run 1 — 10 Nov 2026 15:40–15:44 PST, commit `12bab57`

Command: `verify_cubag.command` on the owner's Mac (Flutter 3.44.8, Dart 3.12.2). Logs: `docs/verify_logs/run1_20261110_1540/`.

| Step | Command | Result |
|---|---|---|
| Analyze | `flutter analyze` | 0 errors, 0 warnings, 3 infos |
| Flutter tests | `flutter test` | 84 passed, 0 failed |
| Android debug | `flutter build apk --debug` | **FAILED** — manifest merger, `usesCleartextTraffic` debug=true vs main=false (pre-existing) |
| Android release | `flutter build appbundle --release` | failed by design — "Release signing is not configured" |
| Pods | `pod install` | OK (28 pods) |
| iOS release | `flutter build ios --release --no-codesign` | OK — `Runner.app` 38.1 MB |
| Backend fake-DB | `pytest tests_security` (macOS venv) | 75 passed |

Fixes after run 1: commit `a8b41f8` (debug manifest `tools:replace`, `RadioGroup` in report dialog, null-aware element in a test). **Not re-verified** until run 2.

## Run 2 — 10 Nov 2026 22:38–22:42 PST, commit `56a077c`

Command: `verify_cubag.command` executed on macOS (Flutter 3.44.8, Dart 3.12.2, Android SDK 36, Xcode 27.2). Logs: `docs/verify_logs/run_20261110_223822/`.

| Step | Command | Result |
|---|---|---|
| Flutter version | `flutter --version` | Flutter 3.44.8, Dart 3.12.2 |
| Pub get | `flutter pub get` | OK (rc=0) |
| Analyze | `flutter analyze --no-fatal-infos --no-fatal-warnings` | **0 errors, 0 warnings, 0 infos** (`No issues found!`) |
| Flutter tests | `flutter test` | **84 passed, 0 failed** |
| Android debug | `flutter build apk --debug` | **PASSED** — `app-debug.apk` built successfully; manifest merge conflict resolved |
| Merged manifest SDK | `grep sdk/traffic` | `minSdkVersion="24"`, `targetSdkVersion="36"` |
| Android release | `flutter build appbundle --release` | failed by design (rc=1) — "Release signing is not configured: create android/key.properties" |
| Pods | `pod install` | OK (28 pods) |
| iOS release | `flutter build ios --release --no-codesign` | **PASSED** — `Runner.app` 38.2 MB |
| Backend collect | `pytest tests_security --collect-only` | OK (75 tests collected) |
| Backend fake-DB | `pytest tests_security` (macOS venv) | **75 passed** |
| Real-PG guard | `pytest tests_pg` (guard step) | **2 passed, 19 skipped** (guard verified; `TEST_DATABASE_URL` unset) |

All checks passed. Android debug build and analyzer fixes confirmed clean. Phase 1 verification complete; SEC-14 unblocked.

## Backend re-runs — 10 Nov 2026 ~16:00–16:12 PST

Fake-DB suite, Linux workspace on the Mac, Python 3.10:

| When (commit) | Command | Result |
|---|---|---|
| `a8b41f8` | `python3 -m pytest tests_security -q -p no:cacheprovider` | 75 passed |
| `71546e0` | same | 75 passed |

## Real PostgreSQL — 10 Nov 2026 ~16:03–16:10 PST

Environment: throwaway PostgreSQL **16.15** cluster on 127.0.0.1 in an isolated cloud sandbox with no route to production; databases `cubag_test`, `cubag_base`, `cubag_rls_test`. The code under test was a `git archive` of the branch (no `.env`, no uploads). Caveat: no `psycopg2` build was installable in that sandbox, so the Python driver was a thin test-only libpq (ctypes) adapter. Every SQL statement was parsed and executed by the real server; driver-specific behaviour of `psycopg2` itself is not covered and should be confirmed by running `tests_pg` on the Mac (instructions in `CUBAG_NEXT_STEPS.md`).

### Schema

| Check | Base `ebc211d` | Branch (after `da03dd5`) |
|---|---|---|
| `init_db()` on an empty database | **fails**: `relation "task_submissions" does not exist`; transaction rolls back, 0 tables | 41 tables created |
| `init_db()` run twice | — | no errors, same table count |
| Tables used by code but created nowhere in the repo | `task_submissions`, `complaints`, `cti_course_enrollments` | `task_submissions` now created; `complaints`, `cti_course_enrollments` still missing (test-only inferred copies in `tests_pg/schema_gaps.sql`) |
| `members.updated_at` (written by delete-account) | not created | created (`ADD COLUMN IF NOT EXISTS`) |

### `tests_pg/` (new, real PostgreSQL)

`TEST_DATABASE_URL="host=127.0.0.1 port=54329 user=postgres dbname=cubag_test" python3 -m pytest tests_pg -q`

| Run | Result |
|---|---|
| First run | 17 passed, 4 failed (2 test mistakes, 2 real findings below) |
| After fixes (`da03dd5`, `e88b117`) | **21 passed** (19 database tests + 2 guard tests) |
| As a non-superuser table owner (`cubag_owner`) | 21 passed |
| `TEST_DATABASE_URL` unset | 2 passed, 19 skipped (app never imported) |
| `TEST_DATABASE_URL` = a remote host | 2 passed, 19 skipped ("refused") |
| Local Mac (`127.0.0.1:5432`, real PostgreSQL + real `psycopg2`) | **21 passed, 0 failed** (11.29s) |

Real findings from this suite:

1. **Account deletion returned 500** — the SEC-07 change on this branch set `password_hash = NULL` on a `NOT NULL` column. Regression introduced by this branch; the fake DB could not detect it. Fixed in `da03dd5`.
2. **Account deletion wrote `members.updated_at`**, a column no code creates. Pre-existing. Fixed in `da03dd5`.
3. **Fresh database cannot be built** (`task_submissions`). Pre-existing. Fixed in `da03dd5`.
4. **`complaints` and `cti_course_enrollments` have no DDL anywhere.** Pre-existing, open (DB-01).

Covered against real PostgreSQL: schema + idempotent init; login (case-insensitive email, wrong password, deleted account); password change bumps `token_version`, old token 401, new token works; delete-account clears credentials/identifiers and data, revokes tokens; suspended member refused; complaints permissions with real `sub_admin_permissions` rows; email-change code flow incl. duplicate address; message send/block/unblock/report rows; CTI iOS block for online/hybrid incl. without `course_id`, in-person and Android not blocked, list flags; receipt signing by real owner row; rollback and pool recovery after a failed statement.

### SEC-10 lockdown migration (local rehearsal only)

Database `cubag_rls_test`, roles `anon`/`authenticated` created locally and granted full access first, to mimic Supabase defaults.

| Step | Result |
|---|---|
| `anon` reads `members` before | allowed |
| Apply `migrations/2026_11_10_sec10_lockdown_supabase_rest.sql` | no errors |
| `anon` reads `members` after | `permission denied for table members` |
| RLS enabled | 45 of 45 public tables |
| `tests_pg` as the table owner after lockdown | 21 passed |

This is a rehearsal on a local copy of the schema. **It has not been run on Supabase.**

### Legacy `tests/` suite (real PostgreSQL, local)

| Code | Result |
|---|---|
| Base `ebc211d` | 71 passed, 11 failed, 4 skipped |
| Branch | 72–73 passed, 9–10 failed, 4 skipped (one test depends on leftover rows) |

All branch failures also fail on the base commit at the same lines, so none were introduced by this branch:

- 6 × `assert 403 == 401` (`test_documents.py` ×3, `test_security_hardening.py` ×3): unauthenticated POSTs are rejected by the CSRF check (403) before authentication (401). Tests are out of date with the middleware order.
- 2 × webhook (`test_security_payments.py`): tests send no `X-Whitsun-Timestamp`, which the handler has required since before this branch.
- 1 × `test_payment_security.py:41`: the payment state machine allows `failed → paid`; the test says it must not. **Needs an owner decision** (is an admin allowed to mark a failed payment paid?).
- 1 × `test_compliance_duplicates.py`: needs member id 1 to exist; passes or fails depending on leftover data. It inserts a compliance application for member 1.
- 4 skipped: need `TEST_ADMIN_EMAIL` / `TEST_ADMIN_PASSWORD`.

Isolation of the legacy suite before this session: none. No test database, no transactions or rollback, and `DB_HOST`/`DB_PASSWORD` came from the developer's `.env` — so `pytest tests` on the Mac would have run `init_db()` DDL and at least one insert against production. Fixed in `e88b117` (local `*_test` database only; otherwise a closed local port).


## SEC-14 — 10–11 Nov 2026 (after run 2)

Order followed: review of the existing flow → design and risks (`CUBAG_SEC14_DESIGN.md`, commit `f3847f8`) → backend → tests → app.

Backend, fake DB (Linux workspace on the Mac, Python 3.10), commit `1e5f797`:

| Command | Result |
|---|---|
| `python3 -m pytest tests_security -q -p no:cacheprovider` | **103 passed** (75 existing + 28 in `test_sec14_biometric_tokens.py`) |

Backend, real PostgreSQL 16.15 (local throwaway cluster, fresh database, same test-only libpq adapter caveat as above), commit `1e5f797`:

| Command | Result |
|---|---|
| `TEST_DATABASE_URL=…cubag_test python3 -m pytest tests_pg -q` | first run: 42 passed, 1 failed (a mistake in the new test's SQL, not in the app) |
| same, after fixing the test | **45 passed** (21 existing + 24 in `test_sec14_biometric_pg.py`), repeated 5 times with the same result |
| Legacy `tests/` | 72 passed, 10 failed, 4 skipped — the same pre-existing failures |

The login refactor (`_complete_login`) is covered by the existing login tests in both suites, which still pass.

Required cases and where they are proven (F = fake DB, P = real PostgreSQL):

| Case | Evidence |
|---|---|
| Valid credential | F, P (signs in, session works, credential replaced, replacement works) |
| Expired | F, P |
| Revoked | F, P |
| Token reuse (rotated credential replayed) | F, P — device revoked, legitimate credential cut off too |
| Simultaneous double use | P — two threads, exactly one 200 and one 401 |
| Device mismatch | F, P |
| Wrong secret / guessing | F, P — revoked after 5 |
| Cross-member use | P |
| Logout | F, P — plain keeps, forget-device revokes one, all-devices revokes all and kills sessions |
| Password change | F, P — incl. re-enrolment needing the new password |
| Password reset | P |
| Account security changes | P — confirmed email change, account deletion, role change to admin, suspension (blocked, not consumed) |
| Unauthorised enrolment / refresh | F, P — no session 401, wrong password 400 + lockout, admin 403, bad device id 400 |
| Secret never stored or logged in clear | F, P |

App (Flutter), commit `11cad02`: **not compiled, not analyzed, not run.** New unit tests in `test/biometric_service_test.dart` have not been executed. Verification run 3 (`verify_cubag.command`) is required before any of it counts as verified, and device rows 9.1–9.11 after that.
