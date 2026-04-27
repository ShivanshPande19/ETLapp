# app/api/routes/complaints.py
from __future__ import annotations
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, Form, HTTPException, Path, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ...database import get_db
from ...models.complaint import Complaint

try:
    from ...core.security import get_current_user
except ImportError:
    try:
        from ...api.deps import get_current_user
    except ImportError:
        def get_current_user():
            return {"id": 0}

router = APIRouter()

_COURT_NAMES = {1: "Court 1", 2: "Court 2", 3: "Court 3"}

_CATEGORIES = [
    ("food",        "\U0001f354", "Food Quality",    "Taste, hygiene, wrong order, cold food"),
    ("staff",       "\U0001f9d1", "Staff Behaviour", "Rude, inattentive, or unprofessional staff"),
    ("cleanliness", "\U0001f9f9", "Cleanliness",     "Dirty tables, floors, or washrooms"),
    ("other",       "\U0001f4cb", "Other Issue",     "Anything else not listed above"),
]


# ─── HTML: Customer complaint form ───────────────────────────────────────────

def _form_html(court_id: int) -> str:
    court_name = _COURT_NAMES.get(court_id, f"Court {court_id}")
    options = ""
    for val, emoji, label, hint in _CATEGORIES:
        options += f"""
        <label class="opt" data-val="{val}">
          <input type="radio" name="category" value="{val}" required hidden>
          <span class="emoji">{emoji}</span>
          <span class="opt-body">
            <span class="opt-title">{label}</span>
            <span class="opt-hint">{hint}</span>
          </span>
          <span class="tick">&#10003;</span>
        </label>"""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Raise a Complaint &middot; {court_name}</title>
<style>
*,*::before,*::after{{box-sizing:border-box;margin:0;padding:0}}
:root{{--black:#0A0A0A;--white:#fff;--grey:#888;--lg:#F2F2F2;--border:#E0E0E0;--r:16px;--font:'Inter',system-ui,sans-serif}}
html{{background:var(--lg);-webkit-text-size-adjust:100%}}
body{{font-family:var(--font);color:var(--black);min-height:100dvh;padding-bottom:env(safe-area-inset-bottom,16px)}}
.hdr{{background:var(--black);padding:20px 20px 18px;position:sticky;top:0;z-index:10}}
.hdr-tag{{font-size:11px;font-weight:600;letter-spacing:1px;color:rgba(255,255,255,.4);text-transform:uppercase;margin-bottom:4px}}
.hdr-title{{font-size:22px;font-weight:800;color:#fff;letter-spacing:-.4px}}
.hdr-sub{{font-size:13px;color:rgba(255,255,255,.4);margin-top:3px}}
form{{padding:20px;display:flex;flex-direction:column;gap:20px}}
.section-label{{font-size:11px;font-weight:700;letter-spacing:.8px;color:var(--grey);text-transform:uppercase;margin-bottom:8px}}
.opts{{display:flex;flex-direction:column;gap:8px}}
.opt{{display:flex;align-items:center;gap:12px;background:var(--white);border:1.5px solid var(--border);border-radius:var(--r);padding:13px 14px;cursor:pointer;transition:border-color .15s,background .15s;-webkit-tap-highlight-color:transparent}}
.opt.selected{{border-color:var(--black);background:#FAFAFA}}
.emoji{{font-size:22px;flex-shrink:0;width:30px;text-align:center}}
.opt-body{{flex:1}}
.opt-title{{font-size:14px;font-weight:700;display:block}}
.opt-hint{{font-size:12px;color:var(--grey);display:block;margin-top:2px}}
.tick{{width:22px;height:22px;border-radius:50%;border:1.5px solid var(--border);font-size:11px;display:flex;align-items:center;justify-content:center;color:transparent;flex-shrink:0;transition:all .15s}}
.opt.selected .tick{{background:var(--black);border-color:var(--black);color:#fff}}
textarea{{width:100%;min-height:110px;padding:14px;background:var(--white);border:1.5px solid var(--border);border-radius:var(--r);font:14px/1.5 var(--font);color:var(--black);resize:none;outline:none;transition:border-color .15s;-webkit-appearance:none}}
textarea:focus{{border-color:var(--black)}}
textarea::placeholder{{color:#BBB}}
.submit-btn{{width:100%;padding:16px;background:var(--black);color:#fff;border:none;border-radius:var(--r);font:700 15px var(--font);cursor:pointer;transition:opacity .15s;-webkit-tap-highlight-color:transparent}}
.submit-btn:active{{opacity:.85}}
.submit-btn:disabled{{opacity:.4;cursor:not-allowed}}
.footer-note{{text-align:center;font-size:11px;color:var(--grey);padding-bottom:12px}}
</style>
</head>
<body>
<div class="hdr">
  <div class="hdr-tag">ETL Food Courts &middot; {court_name}</div>
  <div class="hdr-title">Raise a Complaint</div>
  <div class="hdr-sub">We review every complaint within 24 hours</div>
</div>
<form id="form" method="POST" action="/c/{court_id}/submit">
  <div>
    <div class="section-label">What is your issue about?</div>
    <div class="opts">{options}</div>
  </div>
  <div>
    <div class="section-label">Describe the issue</div>
    <textarea name="description" placeholder="Tell us what happened..." required minlength="10"></textarea>
  </div>
  <button class="submit-btn" type="submit" id="btn">Submit Complaint</button>
  <p class="footer-note">Your feedback is anonymous and helps us improve</p>
</form>
<script>
document.querySelectorAll('.opt').forEach(function(o){{
  o.addEventListener('click',function(){{
    document.querySelectorAll('.opt').forEach(function(x){{x.classList.remove('selected');}});
    o.classList.add('selected');
    o.querySelector('input').checked=true;
  }});
}});
document.getElementById('form').addEventListener('submit',function(){{
  var b=document.getElementById('btn');
  b.disabled=true;b.textContent='Submitting...';
}});
</script>
</body>
</html>"""


def _thanks_html(court_name: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Thank You &middot; ETL Food Courts</title>
<style>
*,*::before,*::after{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:'Inter',system-ui;background:#0A0A0A;color:#fff;min-height:100dvh;
     display:flex;align-items:center;justify-content:center;padding:32px 24px;text-align:center}}
.icon{{font-size:56px;margin-bottom:20px}}
h1{{font-size:24px;font-weight:800;letter-spacing:-.4px;margin-bottom:10px}}
p{{font-size:14px;color:rgba(255,255,255,.5);line-height:1.6;max-width:280px;margin:0 auto}}
.tag{{margin-top:24px;display:inline-block;padding:6px 16px;background:rgba(255,255,255,.08);
      border-radius:999px;font-size:12px;color:rgba(255,255,255,.4)}}
</style>
</head>
<body>
  <div>
    <div class="icon">&#9989;</div>
    <h1>Complaint Received</h1>
    <p>Thank you for letting us know. Our team at {court_name} will review and take action.</p>
    <div class="tag">ETL Food Courts &middot; {court_name}</div>
  </div>
</body>
</html>"""


# ─── PUBLIC endpoints (no auth — customer form) ───────────────────────────────

@router.get("/c/{court_id}", response_class=HTMLResponse, include_in_schema=False)
def complaint_form(court_id: int = Path(..., ge=1, le=3)):
    """QR code target — serves the mobile HTML complaint form."""
    return HTMLResponse(_form_html(court_id))


@router.post("/c/{court_id}/submit", response_class=HTMLResponse, include_in_schema=False)
def submit_complaint(
    court_id:    int = Path(..., ge=1, le=3),
    category:    str = Form(...),
    description: str = Form(..., min_length=5),
    db: Session = Depends(get_db),
):
    """Receives form POST from customer's phone, saves to DB, returns thank-you page."""
    if category not in {"food", "staff", "cleanliness", "other"}:
        raise HTTPException(status_code=422, detail="Invalid category")
    db.add(Complaint(
        court_id=court_id, category=category,
        description=description.strip(), status="open",
    ))
    db.commit()
    return HTMLResponse(_thanks_html(_COURT_NAMES.get(court_id, f"Court {court_id}")))


# ─── PRIVATE endpoints (manager Flutter app — auth required) ─────────────────

class ComplaintOut(BaseModel):
    id: int; court_id: int; category: str; description: str
    status: str; created_at: Optional[str]; resolved_at: Optional[str]
    class Config:
        from_attributes = True

class StatusUpdate(BaseModel):
    status: str   # open | in_progress | resolved


@router.get("/complaints", response_model=List[ComplaintOut])
def get_complaints(
    court_id: Optional[int] = None,
    status:   Optional[str] = None,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """Manager: get all complaints, optionally filtered by court_id or status."""
    q = db.query(Complaint)
    if court_id: q = q.filter(Complaint.court_id == court_id)
    if status:   q = q.filter(Complaint.status   == status)
    rows = q.order_by(Complaint.created_at.desc()).all()
    return [ComplaintOut(
        id=c.id, court_id=c.court_id, category=c.category,
        description=c.description, status=c.status,
        created_at=c.created_at.isoformat() if c.created_at else None,
        resolved_at=c.resolved_at.isoformat() if c.resolved_at else None,
    ) for c in rows]


@router.patch("/complaints/{complaint_id}", response_model=ComplaintOut)
def update_status(
    complaint_id: int,
    body: StatusUpdate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """Manager: change complaint status (open → in_progress → resolved)."""
    if body.status not in {"open", "in_progress", "resolved"}:
        raise HTTPException(status_code=422, detail="Invalid status value")
    c = db.query(Complaint).filter(Complaint.id == complaint_id).first()
    if not c:
        raise HTTPException(status_code=404, detail="Complaint not found")
    c.status = body.status
    if body.status == "resolved":
        c.resolved_at = datetime.now()
    db.commit(); db.refresh(c)
    return ComplaintOut(
        id=c.id, court_id=c.court_id, category=c.category,
        description=c.description, status=c.status,
        created_at=c.created_at.isoformat() if c.created_at else None,
        resolved_at=c.resolved_at.isoformat() if c.resolved_at else None,
    )
