# backend_fastapi/app/services/email_service.py
#
# Transactional email via Resend (https://resend.com).
# If RESEND_API_KEY is not configured, sending is skipped gracefully and the
# caller can fall back to showing/sharing the link manually.

import logging
import httpx

from ..core.config import settings

logger = logging.getLogger("email")

RESEND_URL = "https://api.resend.com/emails"


async def send_email(to: str, subject: str, html: str) -> bool:
    """Send an HTML email. Returns True if Resend accepted it, else False.

    Never raises — email failure must not break the calling flow (e.g.
    onboarding approval still succeeds; the link can be shared manually).
    """
    if not settings.RESEND_API_KEY:
        logger.warning("[EMAIL] RESEND_API_KEY not set — skipping email to %s", to)
        return False

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                RESEND_URL,
                headers={
                    "Authorization": f"Bearer {settings.RESEND_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "from": settings.EMAIL_FROM,
                    "to": [to],
                    "subject": subject,
                    "html": html,
                },
            )
        if resp.status_code in (200, 201):
            logger.info("[EMAIL] sent to %s (subject=%s)", to, subject)
            return True
        logger.error(
            "[EMAIL] Resend failed (%s): %s", resp.status_code, resp.text[:300]
        )
        return False
    except Exception as e:  # noqa: BLE001 — email must never break the flow
        logger.error("[EMAIL] Resend exception: %s", e)
        return False
