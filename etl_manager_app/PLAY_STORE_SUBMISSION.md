# ETL Manager — Google Play Store Submission Guide

> Copy-paste ready answers for every Play Console section, based on a full
> code review of this app. Read the **Blockers** section first — those are the
> things that will get you rejected if not fixed before you submit.

App facts (verified from code):
- **App name (label):** ETL Manager
- **Application ID (package):** `com.azimuth.etl`  ✅ (Play-safe, not `com.example.*`)
- **Version:** 1.0.0 (versionCode 1)
- **Category of app:** Internal business tool — Food Court operations (attendance,
  sales, housekeeping, maintenance, staff & outlet onboarding)
- **Backend:** FastAPI on Railway → `https://etlapp-production.up.railway.app`
- **Access model:** Login only. **No public sign-up** — accounts are created by
  ETL admins/managers. Roles: ETL Manager (admin), Outlet Manager, Staff.

---

## ⛔ BLOCKERS — fix these before submitting

1. **Test login credentials (App access section) — MANDATORY.**
   The whole app is behind a login with no sign-up. Google's review team CANNOT
   test it without a working account. If you skip this, you WILL be rejected.
   → Create a demo account for each role (or at least Manager + Staff) and add
   them under **App access** (see that section below).

2. **Privacy Policy URL — MANDATORY.**
   The app collects personal data (name, email, phone), precise location, and
   photos. Play requires a hosted privacy policy URL. You don't have one yet.
   → A ready-to-host policy draft is in the last section. Host it (e.g. add a
   `/privacy` page to your FastAPI backend, or a GitHub Pages / Google Sites page)
   and paste the URL.

3. **Upload signing key (release keystore).**
   `android/app/build.gradle.kts` falls back to the **debug** key when
   `key.properties` is missing. A debug-signed build is rejected by Play.
   → Generate an upload keystore and fill `android/key.properties` (see the
   "Build & signing" section). Recommended: enroll in **Play App Signing**.

4. **`namespace` still `com.example.etl_manager_app`.**
   The `applicationId` (`com.azimuth.etl`) is what Play uses, so this is not a
   hard blocker, but it's cleaner to align them. Optional.

5. **Verify `targetSdk`.**
   Play requires a recent target API level (API 35 in 2025+). This project uses
   `flutter.targetSdkVersion`, which follows your installed Flutter. Confirm the
   built AAB targets API 35+ before uploading.

---

## 1. Data safety form (App content → Data safety)

This is the section Google scrutinises most. Answers below match what the code
actually does.

**Overview answers:**
- Does your app collect or share any of the required user data types? → **Yes**
- Is all of the user data collected by your app encrypted in transit? → **Yes**
  (all API traffic is HTTPS via Dio to the Railway backend).
- Do you provide a way for users to request that their data be deleted? → **Yes**
  — you must provide a deletion request URL/email (see Privacy Policy). Since
  accounts are org-managed, offer deletion via email/support request.

**Data types collected — declare each as "Collected", sent off-device:**

| Data type | Collected? | Shared? | Processed ephemerally? | Required/Optional | Purpose |
|---|---|---|---|---|---|
| Name | Yes | No | No | Required | App functionality, Account management |
| Email address | Yes | No | No | Required | App functionality, Account management |
| Phone number (onboarding: outlet owner) | Yes | No | No | Required | App functionality |
| Precise location | Yes | No | No | Required | App functionality (attendance geofence check-in) |
| Photos | Yes | No | No | Required | App functionality (attendance selfie, housekeeping/maintenance proof, business docs) |
| Other documents/files (GST, FSSAI, agreements — onboarding) | Yes | No | No | Optional | App functionality |
| App activity / other actions (attendance, sales entries, checklists, complaints) | Yes | No | No | Required | App functionality |

**Notes / clarifications for the form:**
- **Precise location:** Used only in the foreground while marking attendance
  (geofence + selfie watermark). NOT background location. Do NOT declare
  background location — you don't request it.
- **Biometric (fingerprint / Face ID):** This is a LOCAL app-lock via `local_auth`.
  It never leaves the device and is not sent to a server → **do NOT** declare it
  as collected data.
- **Auth token:** Stored on-device in secure storage (Keystore/Keychain). Not a
  declarable "collected" data type.
- **Financial info:** The sales figures are BUSINESS/outlet data, not the app
  user's personal financial info → you generally do not declare this as personal
  "financial info". (If a reviewer asks, explain it's aggregate outlet sales.)
- **No data is "Shared"** with third parties (it goes only to your own backend).
  Petpooja/POS is a server-side integration; the app itself doesn't share.
- **No advertising, no analytics SDKs** found in the code.

---

## 2. App access (App content → App access)

Select: **All or some functionality is restricted** → provide instructions.

Add one entry per role. Example (replace with real demo accounts you create):

```
Name: Manager (Admin) demo
Username/Email: reviewer.manager@etlfoodcourt.com
Password: <demo password>
Any other info: Full admin. Lands on the ETL dashboard (courts, sales,
attendance, staff). No steps needed after login.

Name: Staff demo
Username/Email: reviewer.staff@etlfoodcourt.com
Password: <demo password>
Any other info: Staff view. "Mark Attendance" opens the camera and needs
Location + Camera permission; a geofence may block the shutter if the device
is far from the configured court — this is expected behaviour.
```

> Tip: keep these demo accounts alive and with sample data so re-reviews pass.

---

## 3. Permissions & prominent disclosure

Declared in `AndroidManifest.xml`: `CAMERA`, `ACCESS_FINE_LOCATION`,
`ACCESS_COARSE_LOCATION`, `USE_BIOMETRIC`, `USE_FINGERPRINT`,
`READ/WRITE_EXTERNAL_STORAGE`, `INTERNET`.

- **Location permission declaration:** Because you use `ACCESS_FINE_LOCATION`,
  Play may show a Permissions Declaration form. Answer:
  - Foreground only (no background location).
  - Core purpose: **staff attendance verification (geofence + photo watermark)**.
- **Photos/Storage:** On modern Android, `image_picker`/`camera` use the system
  picker; the `READ/WRITE_EXTERNAL_STORAGE` legacy perms only apply to old APIs.
  Nothing extra to declare, but keep the description accurate.
- There is **no** background location, no "All files access"
  (`MANAGE_EXTERNAL_STORAGE`), no SMS/Call-log permissions → good, those trigger
  extra policy forms and you avoid them.

---

## 4. Store listing (Main store listing)

**App name (30 chars max):**
```
ETL Manager
```

**Short description (80 chars max):**
```
Food court operations: staff attendance, sales, housekeeping & maintenance.
```

**Full description (draft — edit freely; 4000 chars max):**
```
ETL Manager is the internal operations app for ETL Food Courts. It gives court
managers, outlet managers and staff a single place to run day-to-day operations.

Key features:
• Staff attendance — mark attendance with a live selfie and on-site geofence
  verification, so check-ins are tied to the actual court location.
• Sales tracking — view daily and outlet-level sales, synced from POS integrations.
• Housekeeping & checklists — complete and review daily housekeeping tasks with
  photo proof.
• Maintenance & complaints — log and track maintenance requests and complaints,
  including QR-based reporting.
• Outlet onboarding — review outlet applications and required business documents.
• Notices & feedback — share notices across courts and collect feedback.
• Roles & access — tailored views for ETL managers, outlet managers and staff.
• Secure — optional biometric app lock and encrypted, token-based sign-in.

ETL Manager is intended for ETL Food Courts staff and partners. A valid account
provided by ETL is required to sign in.
```

**Other store listing fields:**
- **App category:** Business
- **Tags:** business, productivity/management
- **Contact email:** a monitored ETL support email
- **Website:** your company site (or the backend/company landing page)
- **Privacy policy:** (URL from Blocker #2)

**Graphic assets you must upload:**
- App icon: 512×512 PNG (you already have `assets/icon/app_icon.png` 1024² for
  the launcher — export a 512² for the store).
- Feature graphic: 1024×500 PNG/JPG.
- Phone screenshots: 2–8, e.g. Login, Dashboard, Mark Attendance, Sales,
  Housekeeping, Settings. (No frame/status-bar mock-ups with fake info.)

---

## 5. Content rating (App content → Content rating)

Fill the IARC questionnaire:
- Category: **Utility / Productivity / Communication** (business tool).
- No violence, sexual content, gambling, drugs, or user-generated public content.
- Result will be **Everyone / PEGI 3**. (It's a business tool; content is benign.)

---

## 6. Target audience & other App content forms

- **Target audience:** Adults only (18+). This is a workforce tool — do NOT
  include children's age groups. This keeps you out of Families/child-safety
  policy scope.
- **Ads:** No, the app contains no ads.
- **News app:** No.
- **COVID-19 contact tracing/status:** No.
- **Data safety:** completed in section 1.
- **Government app:** No.
- **Financial features:** No (no personal lending/trading; sales are internal
  business metrics). If asked, clarify it's internal operations data.
- **Health:** No.

---

## 7. Build & signing (for the AAB you upload)

1. Generate an upload keystore once (keep the file + passwords backed up safely —
   losing it means you can never update the app):
   ```
   keytool -genkey -v -keystore ~/etl-upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `android/key.properties` (gitignored) from `key.properties.example`
   with the real path/passwords.
3. Build the release App Bundle:
   ```
   flutter build appbundle --release
   ```
   Output: `build/app/outputs/bundle/release/app-release.aab`
4. Recommended: enable **Play App Signing** in the console (Google manages the
   final signing key; you keep only the upload key).
5. Confirm the bundle's `targetSdk` is 35+ (Blocker #5).

---

## 8. Release track suggestion

Because this is an internal/enterprise tool behind a login:
- Consider **Internal testing** or **Closed testing** first (fast, fewer review
  surprises), then promote to Production.
- If you never want it publicly discoverable, you could distribute privately via
  **Managed Google Play (Google Play for Work)** instead of public Production —
  but public Production is fine as long as you supply the demo credentials above.

---

## 9. Privacy Policy — draft to host

> Host this at a public URL (e.g. add a `/privacy` route to the FastAPI backend,
> or a GitHub Pages page) and paste that URL into the console. Replace the
> bracketed placeholders. This is a starting template, not legal advice.

```
Privacy Policy — ETL Manager

Last updated: [DATE]

ETL Manager ("the app") is an internal operations app provided by
[ETL Food Courts / legal entity name] ("we", "us") for our staff and partners.
This policy explains what data we process and why.

1. Who can use the app
The app is for authorised ETL staff, outlet managers and partners. Accounts are
created by ETL administrators; there is no public sign-up.

2. Data we collect
- Account data: name and email address used to sign in.
- Onboarding data (managers only): outlet owner name, phone, email, and business
  documents (e.g. GST, FSSAI, agreements).
- Location: precise device location, captured only when a staff member marks
  attendance, to verify presence at the assigned court. Location is used in the
  foreground only; we do not track location in the background.
- Photos: attendance selfies and photos taken for housekeeping, maintenance and
  onboarding proof.
- Operational data: attendance records, sales figures, checklists, complaints,
  notices and feedback entered in the app.

3. How we use data
To operate ETL Food Court operations: verifying attendance, tracking sales,
managing housekeeping and maintenance, onboarding outlets, and internal
communication. We do not use the data for advertising.

4. Biometrics
Optional biometric app-lock (fingerprint/Face ID) is processed by your device
only and is never transmitted to or stored by us.

5. Data storage and security
Data is stored on our servers ([hosting provider/region]) and transmitted over
encrypted HTTPS connections. Sign-in uses secure tokens stored on your device.

6. Data sharing
We do not sell your data or share it with third-party advertisers. Data is
processed only by ETL and our service providers strictly to operate the app
(e.g. hosting, POS/email integrations).

7. Data retention and deletion
We retain operational data as needed for business and legal purposes. To request
access to or deletion of your data, contact us at [privacy@yourcompany.com].
We will action verified requests as required by applicable law.

8. Children
The app is intended for adults (18+) in a workplace context and is not directed
to children.

9. Contact
[Company name], [address]
Email: [privacy@yourcompany.com]
```
