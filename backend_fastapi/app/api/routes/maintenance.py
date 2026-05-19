from __future__ import annotations
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, Form, HTTPException, Path, Query
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ...database import get_db
from ...models.maintenance import MaintenanceIssue
# NEW IMPORT: Court table
from ...models.sale import Court

router = APIRouter()


_ISSUE_TYPES = [
    ("electrical",  "⚡", "Electrical",      "Lights, fans, sockets, wiring issues"),
    ("plumbing",    "🔧", "Plumbing",         "Leaks, blocked drains, water supply"),
    ("furniture",   "🪑", "Furniture",        "Broken chairs, tables, counters"),
    ("cleaning",    "🧹", "Deep Cleaning",    "Spill, pest, heavy cleaning needed"),
    ("other",       "📋", "Other Issue",      "Anything else not listed above"),
]


# ── HTML Form ────────────────────────────────────────────────────────────────

def _form_html(court_id: int, court_name: str, cart_id: str) -> str:
    cart_name  = f"Cart {cart_id}"

    options = ""
    for val, emoji, label, hint in _ISSUE_TYPES:
        options += f"""
        <label class="opt" data-val="{val}">
          <input type="radio" name="issue_type" value="{val}" required hidden>
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
<title>Report Issue &middot; {cart_name}</title>
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
input[type=text]{{width:100%;padding:14px;background:var(--white);border:1.5px solid var(--border);border-radius:var(--r);font:14px/1.5 var(--font);color:var(--black);outline:none;transition:border-color .15s;-webkit-appearance:none}}
input[type=text]:focus{{border-color:var(--black)}}
input[type=text]::placeholder{{color:#BBB}}
textarea{{width:100%;min-height:100px;padding:14px;background:var(--white);border:1.5px solid var(--border);border-radius:var(--r);font:14px/1.5 var(--font);color:var(--black);resize:none;outline:none;transition:border-color .15s;-webkit-appearance:none}}
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
  <div class="hdr-tag">{court_name} &middot; {cart_name}</div>
  <div class="hdr-title">Report an Issue</div>
  <div class="hdr-sub">Manager will be notified immediately</div>
</div>
<form id="form" method="POST" action="/m/{court_id}/{cart_id}/submit">
  <div>
    <div class="section-label">Your Name</div>
    <input type="text" name="staff_name" placeholder="Enter your name" required minlength="2">
  </div>
  <div>
    <div class="section-label">Type of Issue</div>
    <div class="opts">{options}</div>
  </div>
  <div>
    <div class="section-label">Describe the problem</div>
    <textarea name="description" placeholder="Describe what needs to be fixed..." required minlength="5"></textarea>
  </div>
  <button class="submit-btn" type="submit" id="btn">Submit Issue</button>
  <p class="footer-note">{court_name} &middot; {cart_name}</p>
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


def _thanks_html(court_name: str, cart_name: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Done &middot; ETL Food Courts</title>
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
    <div class="icon">&#128295;</div>
    <h1>Issue Reported</h1>
    <p>Your report has been sent to the manager. Someone will address it shortly.</p>
    <div class="tag">{court_name} &middot; {cart_name}</div>
  </div>
</body>
</html>"""


# ── Public endpoints (staff scan QR on phone) ────────────────────────────────

@router.get("/m/{court_id}/{cart_id}", response_class=HTMLResponse, include_in_schema=False)
def maintenance_form(
    court_id: int = Path(..., ge=1),
    cart_id:  str = Path(...),
    db: Session = Depends(get_db)
):
    court = db.query(Court).filter(Court.id == court_id, Court.is_active == True).first()
    if not court:
        raise HTTPException(status_code=404, detail="Court not found or inactive")
        
    return HTMLResponse(_form_html(court_id, court.name, cart_id.upper()))


@router.post("/m/{court_id}/{cart_id}/submit", response_class=HTMLResponse, include_in_schema=False)
def submit_maintenance(
    court_id:   int = Path(..., ge=1),
    cart_id:    str = Path(...),
    staff_name: str = Form(..., min_length=2),
    issue_type: str = Form(...),
    description: str = Form(..., min_length=5),
    db: Session = Depends(get_db),
):
    court = db.query(Court).filter(Court.id == court_id, Court.is_active == True).first()
    if not court:
        raise HTTPException(status_code=404, detail="Court not found or inactive")
        
    valid_types = {t[0] for t in _ISSUE_TYPES}
    if issue_type not in valid_types:
        raise HTTPException(status_code=422, detail="Invalid issue type")

    cart_name  = f"Cart {cart_id.upper()}"

    db.add(MaintenanceIssue(
        court_id=court_id,
        court_name=court.name,
        cart_id=cart_id.upper(),
        cart_name=cart_name,
        staff_name=staff_name.strip(),
        issue_type=issue_type,
        description=description.strip(),
        status="open",
    ))
    db.commit()
    return HTMLResponse(_thanks_html(court.name, cart_name))


# ── Private endpoints (manager Flutter app) ──────────────────────────────────

class IssueOut(BaseModel):
    id: int
    court_id: int
    court_name: str
    cart_id: str
    cart_name: str
    staff_name: str
    issue_type: str
    description: str
    status: str
    created_at: Optional[str]
    updated_at: Optional[str]
    resolved_at: Optional[str]

    class Config:
        from_attributes = True


class StatusUpdate(BaseModel):
    status: str  # open | in_progress | resolved


def _fmt(dt) -> Optional[str]:
    return dt.isoformat() if dt else None


def _to_out(i: MaintenanceIssue) -> IssueOut:
    return IssueOut(
        id=i.id,
        court_id=i.court_id,
        court_name=i.court_name,
        cart_id=i.cart_id,
        cart_name=i.cart_name,
        staff_name=i.staff_name,
        issue_type=i.issue_type,
        description=i.description,
        status=i.status,
        created_at=_fmt(i.created_at),
        updated_at=_fmt(i.updated_at),
        resolved_at=_fmt(i.resolved_at),
    )


@router.get("/maintenance", response_model=List[IssueOut])
def list_issues(
    court_id: Optional[int] = Query(None),
    status:   Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    q = db.query(MaintenanceIssue)
    if court_id:
        q = q.filter(MaintenanceIssue.court_id == court_id)
    if status:
        q = q.filter(MaintenanceIssue.status == status)
    return [_to_out(i) for i in q.order_by(MaintenanceIssue.created_at.desc()).all()]


@router.patch("/maintenance/{issue_id}", response_model=IssueOut)
def update_issue_status(
    issue_id: int = Path(..., ge=1),
    body: StatusUpdate = ...,
    db: Session = Depends(get_db),
):
    issue = db.query(MaintenanceIssue).filter(MaintenanceIssue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    if body.status not in {"open", "in_progress", "resolved"}:
        raise HTTPException(status_code=422, detail="Invalid status")
    issue.status = body.status
    if body.status == "resolved":
        issue.resolved_at = datetime.utcnow()
    db.commit()
    db.refresh(issue)
    return _to_out(issue)