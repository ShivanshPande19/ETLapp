from fastapi import APIRouter, Depends, Query
from datetime import date as dt_date
from sqlalchemy.orm import Session

from ...database import get_db                        # ← fixed
from ...schemas.housekeeping import (
    ShiftSubmitRequest, WeeklyTaskDoneRequest, MonthlyTaskDoneRequest,
    SubmitResponse, FullStatusResponse, WeeklyTaskStatus, MonthlyTaskStatus,
)
from ...services import housekeeping_service as svc

router = APIRouter()


@router.post("/submit", response_model=SubmitResponse)
def submit_shift(body: ShiftSubmitRequest, db: Session = Depends(get_db)):
    return svc.submit_shift(db, body)


@router.get("/status", response_model=FullStatusResponse)
def get_status(
    date: str = Query(default=str(dt_date.today())),
    db: Session = Depends(get_db),
):
    return svc.get_full_status(db, date)


@router.patch("/weekly", response_model=WeeklyTaskStatus)
def mark_weekly(body: WeeklyTaskDoneRequest, db: Session = Depends(get_db)):
    return svc.mark_weekly_done(db, body)


@router.patch("/monthly", response_model=MonthlyTaskStatus)
def mark_monthly(body: MonthlyTaskDoneRequest, db: Session = Depends(get_db)):
    return svc.mark_monthly_done(db, body)