"""Public legal pages (privacy policy) served as static HTML.

Hosted automatically by the backend, so the store-required Privacy Policy URL is
simply:  https://etlapp-production.up.railway.app/privacy

⚠️ Before submitting to the stores, replace the [BRACKETED] placeholders below
(contact email, company legal name if different) with your real details.
"""

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter()

_PRIVACY_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Privacy Policy — ETL Manager</title>
<style>
  :root { --red:#d02128; --ink:#111; --muted:#555; }
  * { box-sizing:border-box; }
  body { margin:0; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
         color:var(--ink); line-height:1.65; background:#fafafa; }
  .wrap { max-width:760px; margin:0 auto; padding:32px 20px 72px; }
  header { border-bottom:3px solid var(--red); padding-bottom:16px; margin-bottom:24px; }
  h1 { margin:0 0 4px; font-size:28px; }
  h2 { margin:32px 0 8px; font-size:19px; }
  .muted { color:var(--muted); font-size:14px; }
  ul { padding-left:20px; }
  li { margin:4px 0; }
  a { color:var(--red); }
  code { background:#eee; padding:1px 5px; border-radius:4px; font-size:13px; }
  footer { margin-top:40px; padding-top:16px; border-top:1px solid #e5e5e5; font-size:13px; color:var(--muted); }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>Privacy Policy</h1>
    <div class="muted">ETL Manager &mdash; by Azimuth &middot; Last updated: June 2026</div>
  </header>

  <p>ETL Manager (&ldquo;the App&rdquo;) is an internal operations tool used by the
  managers and staff of ETL (Eat Truck Love) food courts to manage attendance,
  housekeeping, sales insights, feedback and maintenance. This policy explains
  what information we collect, why, and how it is handled.</p>

  <h2>1. Information we collect</h2>
  <ul>
    <li><strong>Account &amp; profile:</strong> name, email address, phone number,
        role, assigned court/outlet, and (optionally) a profile photo.</li>
    <li><strong>Attendance:</strong> a check-in/out photo (selfie), your device
        location <em>at the moment of check-in only</em>, and timestamps.</li>
    <li><strong>Onboarding (for applicants):</strong> details and documents you
        submit through the onboarding form.</li>
    <li><strong>Operational data:</strong> housekeeping task completions,
        customer feedback, and maintenance tickets you create.</li>
    <li><strong>Technical data:</strong> basic device/app information and logs
        needed to operate the service securely.</li>
  </ul>

  <h2>2. How we use your information</h2>
  <ul>
    <li>Verify attendance at the correct court/outlet and maintain rosters.</li>
    <li>Run daily operations (housekeeping, maintenance, feedback, sales views).</li>
    <li>Send account and operational notifications.</li>
    <li>Protect the service and prevent unauthorised access.</li>
  </ul>

  <h2>3. Location</h2>
  <p>Location is accessed <strong>only while the app is open</strong> and only to
  confirm that an attendance check-in happens within the assigned location&rsquo;s
  geofence. The app does not track your location in the background.</p>

  <h2>4. Camera &amp; photos</h2>
  <p>The camera / photo library is used to capture attendance selfies and to
  upload onboarding documents. These are stored securely and used only for the
  purposes above.</p>

  <h2>5. Sharing &amp; third-party services</h2>
  <p>We do not sell your personal data. We use a small number of service
  providers strictly to run the app:</p>
  <ul>
    <li><strong>Railway</strong> &mdash; application hosting &amp; database.</li>
    <li><strong>Resend</strong> &mdash; sending transactional emails
        (e.g. set-password links).</li>
    <li><strong>Petpooja</strong> &mdash; point-of-sale integration for sales
        figures (business data, not customer personal data).</li>
  </ul>

  <h2>6. Data retention</h2>
  <p>We keep your information for as long as your account is active and as needed
  for legitimate operational, legal and security purposes. You may request
  deletion of your account data by contacting us.</p>

  <h2>7. Security</h2>
  <p>Data is transmitted over encrypted HTTPS connections, access is protected by
  authenticated, role-based accounts, and passwords are stored only as secure
  hashes.</p>

  <h2>8. Your rights</h2>
  <p>You may request access to, correction of, or deletion of your personal data.
  To do so, contact us at the email below.</p>

  <h2>9. Children</h2>
  <p>This app is intended for use by employees and authorised personnel and is not
  directed at children under 13.</p>

  <h2>10. Changes to this policy</h2>
  <p>We may update this policy from time to time. Material changes will be
  reflected on this page with an updated date.</p>

  <h2>11. Contact</h2>
  <p>Questions about this policy or your data? Contact us at
  <a href="mailto:[YOUR-CONTACT-EMAIL]">[YOUR-CONTACT-EMAIL]</a>.</p>

  <footer>
    &copy; 2026 Azimuth &middot; ETL (Eat Truck Love). This policy applies to the
    ETL Manager mobile application.
  </footer>
</div>
</body>
</html>
"""


@router.get("/privacy", include_in_schema=False)
def privacy_policy():
    return HTMLResponse(content=_PRIVACY_HTML)
