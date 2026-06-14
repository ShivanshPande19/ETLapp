# app/api/routes/attendance.py

from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db

from app.models.attendance import Attendance
from app.models.staff import Staff  
import httpx 
import shutil
import os
import uuid

router = APIRouter()

# 🌍 Free Reverse Geocoding API
async def get_address_from_coords(lat: float, lng: float) -> str:
    url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lng}&format=json"
    headers = {"User-Agent": "ETL_Manager_App/1.0"}
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, headers=headers)
            if response.status_code == 200:
                data = response.json()
                return data.get("display_name", f"Lat: {lat}, Lng: {lng}")
    except Exception:
        pass
    return f"Lat: {lat}, Lng: {lng}"

@router.post("/check-in")
async def mark_attendance(
    email: str = Form(...), # ✅ FIXED: Ab 'staff_id' nahi 'email' maang raha hai
    lat: float = Form(...),
    lng: float = Form(...),
    photo: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    # 1. Staff ko Email se dhoondho
    staff = db.query(Staff).filter(Staff.email == email).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found")

    # 2. Photo Save karo (Temporary directory mein)
    os.makedirs("uploads/attendance", exist_ok=True)
    file_ext = photo.filename.split('.')[-1]
    file_name = f"{uuid.uuid4()}.{file_ext}"
    file_path = f"uploads/attendance/{file_name}"
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(photo.file, buffer)
        
    # 3. Address nikaalo
    real_address = await get_address_from_coords(lat, lng)

    # 4. Database Save 
    new_record = Attendance(
        staff_id=staff.id, # Staff id yahan lag jayegi
        outlet_id=staff.outlet_id, 
        court_id=staff.court_id,   
        check_in_lat=lat,
        check_in_lng=lng,
        check_in_address=real_address,
        check_in_photo_url=file_path
    )
    
    db.add(new_record)
    db.commit()
    db.refresh(new_record)

    return {
        "status": "success", 
        "message": "Attendance marked successfully!",
        "address": real_address
    }