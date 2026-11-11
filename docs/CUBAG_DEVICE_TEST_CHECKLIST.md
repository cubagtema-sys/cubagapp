# CUBAG — Mobile Device Test Checklist

Purpose: record what has actually been exercised on a simulator or a phone. Backend tests and successful builds do not count as device verification.

**Status as of 10 Nov 2026: no item below has been tested on a simulator or a physical device.**

## How to fill this in

For each row write the result in the last two columns: `PASS`, `FAIL` (with a note) or leave `Not tested`. Add tester, date, device/OS and build commit at the bottom.

Setup: a build of branch `release/p0-hardening` pointed at a **non-production** backend running the same branch, with at least: two active member accounts (A and B), one admin (web), and three CTI courses with modes Online, Hybrid and In-Person. Do not test with real money; use the gateway's test mode or stop at the payment prompt.

Column meanings: **Backend** = fake-DB unit (`tests_security`) / real PostgreSQL (`tests_pg`). **Flutter unit** = `flutter test`. Builds: iOS release build passed in run 1; no Android build has passed yet.

## 1. Course payment screens — iOS

| # | Step | Expected | Backend | Flutter unit | Simulator | Physical device |
|---|---|---|---|---|---|---|
| 1.1 | Open CTI Courses | Every course shows a delivery-mode badge | Tested (fake + real PG) | Tested (policy logic) | Not tested | Not tested |
| 1.2 | Open an **Online** course | Details and enrolment status shown; **no** Enroll/Pay button, no price call-to-action, no link or wording about paying elsewhere | Tested | Tested | Not tested | Not tested |
| 1.3 | Open a **Hybrid** course | Same as 1.2 | Tested | Tested | Not tested | Not tested |
| 1.4 | Open an **In-Person** course | "Enroll Now" and "Pay in app" shown; payment sheet opens | Tested (not blocked) | Tested | Not tested | Not tested |
| 1.5 | Guest service request → pick an Online course | Button reads "Submit Enrolment Request"; no payment dialog | Tested (403 if attempted) | Not tested | Not tested | Not tested |
| 1.6 | Pay dues / registration / renewal | Unchanged; payment works | Tested (not blocked) | Not tested | Not tested | Not tested |

## 2. Course payment screens — Android

| # | Step | Expected | Backend | Flutter unit | Emulator | Physical device |
|---|---|---|---|---|---|---|
| 2.1 | Online, Hybrid, In-Person courses | All three show "Enroll Now" and can reach the payment sheet | Tested | Tested | Not tested | Not tested |
| 2.2 | Dues / registration / renewal | Unchanged | Tested | Not tested | Not tested | Not tested |

## 3. Email-change verification code

| # | Step | Expected | Backend | Flutter unit | Simulator | Physical device |
|---|---|---|---|---|---|---|
| 3.1 | Profile → change email → Save | Dialog asks for the code sent to the **new** address; email not changed yet | Tested (fake + real PG) | Not tested | Not tested | Not tested |
| 3.2 | Enter a wrong code | Error; email unchanged | Tested | Not tested | Not tested | Not tested |
| 3.3 | Enter the right code | Email updated; stays signed in | Tested | Not tested | Not tested | Not tested |
| 3.4 | Cancel the dialog | Email unchanged; other profile edits behave sensibly | Not tested | Not tested | Not tested | Not tested |
| 3.5 | The code email actually arrives | Received at the new address | Not tested (email is disabled in tests) | — | Not tested | Not tested |

## 4. Sign-out after password change

| # | Step | Expected | Backend | Flutter unit | Simulator | Physical device |
|---|---|---|---|---|---|---|
| 4.1 | Sign in on devices X and Y. On X: Settings → change password | X stays signed in (fresh token saved) | Tested (fake + real PG) | Not tested | Not tested | Not tested |
| 4.2 | Use the app on Y | Y is returned to the login screen on its next request | Tested (old token → 401) | Not tested | Not tested | Not tested |
| 4.3 | On X enter a wrong current password | Error message; X is **not** signed out | Tested (400) | Not tested | Not tested | Not tested |
| 4.4 | Forgot-password reset, then use an old session | Old session signed out | Tested | Not tested | Not tested | Not tested |

## 5. Signed document links

| # | Step | Expected | Backend | Flutter unit | Simulator | Physical device |
|---|---|---|---|---|---|---|
| 5.1 | Member opens own receipt / uploaded document | Opens | Tested (fake + real PG) | Not tested | Not tested | Not tested |
| 5.2 | PDF on Android | Renders inside the app; not via Google Docs viewer | — | Not tested | Not tested | Not tested |
| 5.3 | Copy a document link, wait 6 minutes, open it in a browser | Refused (link expired) | Not tested (no expiry test exists) | — | Not tested | Not tested |
| 5.4 | Admin (web) opens a member's compliance document | Opens | Tested | Not tested | Not tested (web) | — |
| 5.5 | Profile photos, gallery, news images | Still load | Tested (public URLs unchanged) | Not tested | Not tested | Not tested |

## 6. Messaging — report

| # | Step | Expected | Backend | Flutter unit | Simulator | Physical device |
|---|---|---|---|---|---|---|
| 6.1 | In a chat with B: menu → Report member | Reason list + details field | — | Not tested | Not tested | Not tested |
| 6.2 | Submit | Confirmation; B is also blocked | Tested (fake + real PG) | Not tested | Not tested | Not tested |
| 6.3 | Admin (web) sees the report | Listed in the report queue | Tested (API only; **no admin screen exists yet**) | — | — | — |

## 7. Messaging — block

| # | Step | Expected | Backend | Flutter unit | Simulator | Physical device |
|---|---|---|---|---|---|---|
| 7.1 | A blocks B | Menu now shows Unblock | Tested | Not tested | Not tested | Not tested |
| 7.2 | B sends A a message | Refused with a neutral message | Tested (403) | Not tested | Not tested | Not tested |
| 7.3 | A unblocks B; B sends again | Delivered | Tested | Not tested | Not tested | Not tested |
| 7.4 | Message longer than 2,000 characters | Refused | Tested | Not tested | Not tested | Not tested |

## 8. Authentication and session persistence

| # | Step | Expected | Backend | Flutter unit | Simulator | Physical device |
|---|---|---|---|---|---|---|
| 8.1 | Sign in, force-quit, reopen | Still signed in | — | Not tested | Not tested | Not tested |
| 8.2 | Upgrade from the current store/TestFlight build while signed in | Still signed in (token migrated to secure storage) | — | Not tested | Not tested | Not tested |
| 8.3 | Android: inspect shared prefs after login (`adb shell run-as … cat shared_prefs/*.xml`) | No token present | — | Not tested | Not tested | Not tested |
| 8.4 | Sign out, reopen | Login screen | — | Not tested | Not tested | Not tested |
| 8.5 | Release build, server unreachable | No "Configure Server Connection" link | — | Not tested | Not tested | Not tested |
| 8.6 | Fresh install | No notification prompt until after login | — | Not tested | Not tested | Not tested |
| 8.7 | Delete account in app, then try to sign in | Refused | Tested (fake + real PG) | Not tested | Not tested | Not tested |
| 8.8 | Rotate a phone | Stays portrait | — | Not tested | Not tested | Not tested |

## 9. Biometric authentication and token revocation

SEC-14 (revocable biometric tokens) is **not implemented yet**. Today the app stores the account password in the keychain for biometric login. These rows are the acceptance test for SEC-14 and are all `Not tested`.

| # | Step | Expected after SEC-14 | Backend | Flutter unit | Simulator | Physical device |
|---|---|---|---|---|---|---|
| 9.1 | Enable biometric login | Works; the password is not stored on the device | Not implemented | Not tested | Not tested | Not tested |
| 9.2 | Sign out, sign in with Face ID / fingerprint | Works | Not implemented | Not tested | Not tested | Not tested |
| 9.3 | Change password on another device, then use biometrics here | Refused; asks for the password | Not implemented | Not tested | Not tested | Not tested |
| 9.4 | Disable biometric login, then try the old credential | Refused | Not implemented | Not tested | Not tested | Not tested |
| 9.5 | Add a new fingerprint/face in system settings | Biometric login requires the password once | Not implemented | Not tested | Not tested | Not tested |
| 9.6 | Upgrade with biometric login already enabled | Old stored password removed; user asked to re-enable | Not implemented | Not tested | Not tested | Not tested |

Biometric rows need a physical device (or a simulator with enrolled Face ID/Touch ID for 9.1–9.4).

## Sign-off

| Tester | Date | Device / OS | Build commit | Backend commit | Notes |
|---|---|---|---|---|---|
| | | | | | |
