# CUBAG — Store Readiness (Google Play & Apple App Store)

**Date:** 10 November 2026 · **Based on:** static code review of `cubag_flutter/` plus current published requirements (sources at the end).
**No guarantee of approval.** Store review is discretionary. This document lists what the code shows today against each requirement, so the gaps can be closed before submission.

Legend — **Type:** `MANDATORY` (always required), `DEPENDS` (required because of something CUBAG does), `RECOMMENDED` (reduces rejection risk or improves quality).
**Status:** ❌ not met · ⚠️ partially met / unverified · ✅ met (by code inspection).

---

## 1. App identity & build

| # | Requirement | Type | Android | iOS | Evidence / action |
|---|---|---|---|---|---|
| 1.1 | Permanent app identifier | MANDATORY | ⚠️ `com.cubag_flutter` | ✅ `com.cubag.app` | IDs differ. Android's ID can't change after the first Play upload. **Decide now:** if not yet published, change Android to `com.cubag.app` (update `namespace`, `applicationId`, the Kotlin package folder, and re-download `google-services.json`). |
| 1.2 | Release signing | MANDATORY | ❌ falls back to **debug** key (`build.gradle.kts:55-60`; no `key.properties`) | ⚠️ Team `FV6429V895` set; distribution profile not verifiable | Create an upload keystore, enrol in Play App Signing, and make release builds fail without it. iOS: archive with an App Store distribution profile. |
| 1.3 | Android target API | MANDATORY | ⚠️ `targetSdk = flutter.targetSdkVersion` | — | **Google Play: new apps and updates must target Android 16 (API 36) since 31 Aug 2026.** Check the generated value (`flutter build appbundle` then inspect the merged manifest), or set `targetSdk = 36` explicitly. |
| 1.4 | iOS SDK / Xcode | MANDATORY | — | ⚠️ unverified | **Apple: uploads must be built with Xcode 26+ and the iOS 26 SDK since 28 Apr 2026.** Deployment target 15.0 is fine. |
| 1.5 | 16 KB page-size support (native libs) | MANDATORY (targets Android 15+) | ⚠️ unverified | — | Plugins with native code: `mobile_scanner` (ML Kit), `local_auth`, `flutter_secure_storage`, `printing`, `webview_flutter`. Check APK Analyzer / Play pre-launch report for "16 KB alignment"; update plugins if flagged. |
| 1.6 | Version numbering | MANDATORY | ✅ `1.0.0+1` | ✅ | Increment the build number for every upload. |
| 1.7 | Edge-to-edge (Android 15+) | MANDATORY behaviour | ⚠️ | — | Enforced when targeting API 35+. `systemNavigationBarColor` in `main.dart` is ignored there. Test every screen without an AppBar. |
| 1.8 | Crash-free launch & core flows | MANDATORY | Crashlytics wired in code (BUG-04, `422b79c`); not yet built or seen in the console | ⚠️ | Run verification 4, enable Crashlytics in Firebase, add iOS dSYM upload phase, force a test crash on a release build; run the core-flow smoke test |

## 2. App icon, splash and listing assets

| # | Requirement | Type | Status | Action |
|---|---|---|---|---|
| 2.1 | High-quality app icon (iOS 1024×1024 no alpha; Play 512×512) | MANDATORY | ⚠️ dimensions OK, quality ❌ | Source `assets/images/logo.jpeg` is **237×229 px**, non-square, upscaled. Commission a vector or ≥1024 px square master. iOS 1024 icon is RGB (no alpha) ✅. |
| 2.2 | Android adaptive icon | RECOMMENDED | ❌ only legacy `ic_launcher.png` | Add foreground/background layers (`adaptive_icon_foreground` in `flutter_launcher_icons`). |
| 2.3 | Launch screen | MANDATORY (iOS storyboard) | ✅ `LaunchScreen.storyboard` | Regenerate with the new logo; Android 12 splash icon needs safe-zone padding. |
| 2.4 | Screenshots | MANDATORY | ❌ not in repo | iPhone 6.9" (1320×2868 or 1290×2796) required; **iPad 13" required if iPad stays enabled**; Play: at least 2 phone screenshots, a 1024×500 feature graphic, and 7"/10" tablet screenshots if you declare tablet support. Use a demo account with realistic, non-personal data. |
| 2.5 | Store description & metadata accuracy | MANDATORY | ⚠️ | Don't describe the static "market intelligence"/vessel data as live (Apple 2.3). |

## 3. Privacy, data and account

| # | Requirement | Type | Status | Evidence / action |
|---|---|---|---|---|
| 3.1 | Privacy policy — **public URL** in both consoles, plus in-app access | MANDATORY | ⚠️ in-app only (`in_app_legal_viewer.dart:122`) | Publish it at a stable URL (e.g. `https://cubag.org/privacy`) and link to it from Settings. |
| 3.2 | Privacy policy — accurate content | MANDATORY | ❌ | It currently claims "PCI-DSS compliant gateways", "TLS 1.3", "AES-256 data storage", "cryptographic QR verifications" — none of these are evidenced (documents are in public storage URLs, cache is unencrypted, QR is not signed). It doesn't name processors (Firebase/Google, Supabase, Fly.io, WhitsunPay, email provider, Google Fonts, aisstream.io, Sentry), retention periods, deletion process, legal basis, or the data controller's registration under Ghana's Data Protection Act, 2012 (Act 843). Rewrite with legal review. |
| 3.3 | In-app account deletion (Apple 5.1.1(v)); Play account-deletion requirement | MANDATORY | ⚠️ UI exists (`settings_page.dart:96-210`), backend incomplete | Backend soft-deletes and still allows login by licence number (audit SEC-07). Make deletion real; explain any retained payment records. |
| 3.4 | **Play: web link for deletion requests** (without reinstalling the app) | MANDATORY (Play) | ❌ | Publish a page or form (e.g. `cubag.org/delete-account`) and enter it in Data safety. |
| 3.5 | Play **Data safety** form | MANDATORY | ❌ not started | See §6 for the data inventory to declare. |
| 3.6 | Apple **App Privacy** ("nutrition label") | MANDATORY | ❌ not started | Same inventory; mark data as "Linked to user"; tracking = **No** (no ad/tracking SDKs found) — so **App Tracking Transparency is not required**. |
| 3.7 | Apple **privacy manifest** (`PrivacyInfo.xcprivacy`) | MANDATORY for required-reason APIs | ⚠️ none at app level | Add an app-level manifest declaring UserDefaults (CA92.1) and file-timestamp reasons as applicable; plugins ship their own. Check Xcode's generated privacy report after archiving. |
| 3.8 | Data in transit | MANDATORY (iOS ATS) | Android ✅ cleartext off; iOS ❌ | `Info.plist:54-60` sets `NSAllowsArbitraryLoads = true` and `NSAllowsLocalNetworking`. Remove both (the API is HTTPS). |
| 3.9 | Sensitive data handling (documents, IDs, payment slips) | MANDATORY (policy) | ❌ | Public URLs for documents (audit SEC-04). Fix before collecting real member documents through the store build. |
| 3.10 | Sign in with Apple | DEPENDS | ✅ **not required** | Only first-party email/phone + password login; no Google/Facebook login. If you add any third-party login later, Apple 4.8 then applies. |
| 3.11 | App Tracking Transparency | DEPENDS | ✅ not required | No IDFA or tracking SDK found. |

## 4. Permissions

| Permission | Platform | Declared | Used where | Status | Action |
|---|---|---|---|---|---|
| Notifications | Android 13+ `POST_NOTIFICATIONS`, iOS | ✅ | Push (FCM) | ⚠️ requested at cold start before login (`main.dart:128` → `push_notification_service.dart:59-70`) | Ask after login with an in-context explainer. |
| Camera | Android `CAMERA`, iOS `NSCameraUsageDescription` | ✅ | QR scanner **only in admin pages** (`admin_events_page.dart:538`), which are blocked on mobile | ❌ declared without a reachable feature | Remove the permission (and `mobile_scanner`) from the mobile build, or expose check-in scanning to authorised staff on mobile. |
| Photo library | iOS `NSPhotoLibraryUsageDescription` | ✅ | Document/profile uploads via `file_picker` | ✅ | Wording OK. Android: `file_picker` uses the system picker (no storage permission needed on 13+). |
| Storage (legacy) | Android `READ_EXTERNAL_STORAGE ≤32`, `WRITE ≤28` | ✅ | Downloads on old Android | ✅ | Fine (scoped by maxSdkVersion). |
| Calendar | iOS (3 keys) | ✅ | `add_2_calendar` | ✅ | Prefer write-only access on iOS 17+ (already declared). |
| Face ID / biometrics | iOS `NSFaceIDUsageDescription`, Android `USE_BIOMETRIC` | ✅ | Biometric login | ✅ | See audit SEC-14 (stores password). |
| Local network | iOS `NSLocalNetworkUsageDescription` | ❌ says "development backend server" | Developer server dialog | ❌ | Remove the key and the dialog. |
| `USE_FINGERPRINT`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED` | Android | ✅ | local notifications / legacy biometrics | ✅ | OK. Remove `RECEIVE_BOOT_COMPLETED` if you don't schedule local notifications. |
| Location | — | not declared | — | ✅ | Not used. |
| Background modes | iOS `fetch`, `processing`, `remote-notification` | ⚠️ | Only `remote-notification` is needed for FCM | ❌ | Remove `fetch`/`processing` (no `BGTaskScheduler` use; `processing` without `BGTaskSchedulerPermittedIdentifiers` causes an upload warning, and unused modes are a 2.5.4 rejection reason). |

## 5. Content, functionality and review access

| # | Requirement | Guideline | Type | Status | Action |
|---|---|---|---|---|---|
| 5.1 | No test/debug features in production | Apple 2.1/2.3; Play policy | MANDATORY | ❌ | Remove the "Configure Server Connection" dialog with LAN IP `192.168.4.127` (`login_page.dart:92-260, 623-640`) and the `custom_api_url` override. |
| 5.2 | Reviewer can access all features | Apple 2.1 ("App Review Information"); Play "App access" | MANDATORY | ❌ | New accounts are gated behind admin approval + registration fee; admins are blocked on mobile. Create a **dedicated, fully active member demo account** on production (or a reviewer-visible staging setup) with sample documents, payments history, a pending bill, and messages. Put credentials and a short walkthrough in review notes. |
| 5.3 | User-generated content controls | Apple 1.2; Play UGC policy | DEPENDS (member messaging exists) | ❌ | Add: report message/user, block user, a filtering/moderation process, published contact info, and terms that forbid abusive content. Alternatively, restrict messaging to member ↔ Secretariat only for v1 (much smaller scope). |
| 5.4 | Payments | Apple 3.1.1 / 3.1.3; Play Payments policy | DEPENDS | ⚠️ | **Association dues, registration, licence renewal** = real-world professional services → external payment (MoMo/bank) is generally allowed (Apple 3.1.3(e); Play exempts physical goods/services). **CTI courses**: admins can set mode "Online"/"Hybrid". Paying in-app via MoMo for *online* course content is a likely Apple 3.1.1 rejection (digital content requires IAP). Options: (a) hide course payment on iOS and handle enrolment fees off-app; (b) offer only in-person courses for payment in-app; (c) implement IAP for online courses. Product decision required. |
| 5.5 | Accurate data | Apple 2.3, 5.x | RECOMMENDED | ⚠️ | Static vessel ETAs and default market data (audit BUG-10) — label as reference or hide. |
| 5.6 | Minimum functionality / not a web wrapper | Apple 4.2 | RECOMMENDED | ✅ | Native Flutter UI with offline cache, push, biometrics — fine. Some screens embed webviews (`iframe_widget.dart`, `vessel_map_html.dart`); keep these secondary. |
| 5.7 | Content rating | Play questionnaire; Apple age rating (updated system, answers required since 31 Jan 2026) | MANDATORY | ❌ | Declare: users can interact/communicate (messaging); no gambling, violence or mature content. Expect Play "Teen"/IARC 12+ type rating because of unmoderated communication, unless messaging is restricted. |
| 5.8 | Accessibility | Apple (Accessibility Nutrition Labels, optional); Play quality | RECOMMENDED | ⚠️ | Text scaling capped at 1.15×; few semantic labels; brand orange text fails contrast (audit UI-02–UI-04). Not a rejection reason today, but fix before marketing it as accessible. |
| 5.9 | iPad quality | Apple 2.4.1 (iPhone apps should run on iPad) | DEPENDS (`TARGETED_DEVICE_FAMILY = 1,2`) | ⚠️ | Native iPad support is declared, so the reviewer may test on iPad. Either set iPhone-only for v1 or test and fix iPad layouts (audit RESP-01). |
| 5.10 | Push notifications work | Functional | DEPENDS | ❌ iOS | Entitlements not linked in Xcode (audit BUG-01); APNs key must be in Firebase. |
| 5.11 | Business/organisation identity | Apple 5.1.1 / developer program; Play developer verification | RECOMMENDED | ⚠️ | An app representing an official association should be published under **CUBAG's own organisation developer accounts** (D-U-N-S number), not a personal account. Play: organisation accounts skip the 12-tester/14-day closed-test requirement that applies to new personal accounts. |
| 5.12 | Official sender identity | Trust/phishing | RECOMMENDED | ❌ | OTP and reset emails come from non-CUBAG domains (`fly.toml`, `render.yaml`). Use a CUBAG domain. |
| 5.13 | Third-party SDK compliance | Play SDK policy; Apple privacy manifests | MANDATORY | ⚠️ | SDKs in use: Firebase Core/Messaging, Google Fonts (runtime fetching), Socket.IO, ML Kit (via mobile_scanner), WebView. All are mainstream; declare Firebase in Data safety/App Privacy; disable Google Fonts runtime fetching or declare it. |

## 6. Data inventory (for Data safety & App Privacy)

Derived from registration (`auth.py:261-330`), profile, documents, payments, messaging and push code.

| Data type | Collected | Purpose | Shared with (processor) | Optional? |
|---|---|---|---|---|
| Name, email, phone | Yes | Account, communication | Supabase (DB), email provider, Firebase (push token linkage) | Required |
| Company, location, digital address, port of operation | Yes | Membership administration | Supabase | Required |
| TIN / licence number / agency code | Yes | Regulatory verification | Supabase | Required (TIN) |
| Identity & compliance documents (images/PDF) | Yes | Membership vetting, renewal | Supabase Storage | Required for membership |
| Profile photo | Yes | Member card, directory | Supabase Storage | Optional |
| Payment info: MoMo number, bank name/account, receipts, transaction history | Yes | Dues and fees | WhitsunPay, Supabase | Required to pay |
| Messages (member ↔ member/secretariat) | Yes | Communication | Supabase | Optional |
| Survey responses, event registrations, course enrolment | Yes | Engagement | Supabase | Optional |
| Complaints (name, email, phone, description) — includes guests | Yes | Grievance handling | Supabase | Optional |
| Device push token | Yes | Notifications | Firebase Cloud Messaging | Optional |
| Biometric data | **No** (handled on-device by OS) | — | — | — |
| Crash/diagnostics | Crash logs and diagnostics via Firebase Crashlytics (release builds; not linked to the member; tokens, e-mails and numbers scrubbed) | App stability | Google (Firebase) | Declare: Play Data safety → *App info and performance → Crash logs, Diagnostics* (collected, not shared, not linked); App Store → *Diagnostics → Crash Data* (not linked, not tracking) |
| Location, contacts, advertising ID | No | — | — | — |

Encryption in transit: **Yes** for the API (HTTPS); Android cleartext disabled; fix iOS ATS (3.8). Deletion: in-app + web link (3.3–3.4).

## 7. Submission checklist (do in this order)

1. Close all **P0** items in `CUBAG_MASTER_CHECKLIST.md` (security + store blockers).
2. Build with the current Flutter stable that targets API 36 and Xcode 26 / iOS 26 SDK.
3. Internal testing track (Play) + TestFlight internal: run the smoke test on at least iPhone SE, a large iPhone, a 6" Android (API 26-ish) and an Android 15/16 device (and iPad if enabled).
4. Prepare the demo account and review notes (5.2).
5. Publish the privacy policy URL, terms URL and deletion URL; fill Data safety, App Privacy, content rating and age rating.
6. Upload screenshots/feature graphic made from the demo account.
7. Submit Play production (or closed testing if the account is personal) and App Store review. Allow 1–3 review rounds.

---

### Sources
- Google Play target API level requirements — https://developer.android.com/google/play/requirements/target-sdk ("New apps and app updates must target Android 16 (API level 36) or higher" from 31 Aug 2026)
- Apple upcoming requirements — https://developer.apple.com/news/upcoming-requirements/ (Xcode 26 / iOS 26 SDK from 28 Apr 2026; updated age-rating questions by 31 Jan 2026)
- Apple App Review Guidelines — https://developer.apple.com/app-store/review/guidelines/ (1.2, 2.1, 2.3, 2.5.4, 3.1.1, 3.1.3, 4.8, 5.1.1(v))
- Play Console Help: Data safety / account deletion — https://support.google.com/googleplay/android-developer/answer/13327111
- Expo blog on the 2026 App Store minimum SDK — https://expo.dev/blog/app-store-connect-minimum-sdk-26
