# backend_fastapi/app/api/routes/music.py

from fastapi import APIRouter, HTTPException
import spotipy
from spotipy.oauth2 import SpotifyOAuth
from pydantic import BaseModel
from app.core.config import settings
import sqlite3  # <-- Seedha DB se connect karne ke liye
import os

router = APIRouter()

print(f"DEBUG: Client ID Loaded from settings: {settings.spotify_client_id}")

# In-memory store (Court ID -> Device Details)
device_mapping = {}

# Spotify OAuth Configuration
sp_oauth = SpotifyOAuth(
    client_id=settings.spotify_client_id,
    client_secret=settings.spotify_client_secret,
    redirect_uri=settings.spotify_redirect_uri,
    scope="user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private",
    cache_path=".spotify_cache"
)

# Helper function to get active Spotify Client
def get_spotify_client():
    token_info = sp_oauth.get_cached_token()
    if not token_info or sp_oauth.is_token_expired(token_info):
        raise HTTPException(status_code=401, detail="Not authenticated with Spotify")
    return spotipy.Spotify(auth=token_info['access_token'])

# --- Helper Function: Strictly get linked device ---
def get_linked_device_id(court_id: int):
    if not court_id:
        raise HTTPException(status_code=400, detail="Please select a specific court first.")
    
    linked_data = device_mapping.get(court_id)
    if not linked_data or not linked_data.get('id'):
        raise HTTPException(status_code=400, detail=f"No tablet linked to Court {court_id}. Please link a device first.")
    
    return linked_data['id']

# --- 1. Auth Endpoints ---
@router.get("/auth/status")
def get_auth_status():
    token_info = sp_oauth.get_cached_token()
    is_auth = False
    if token_info:
        is_auth = not sp_oauth.is_token_expired(token_info)
    return {"is_authenticated": is_auth}

@router.get("/auth/url")
def get_auth_url():
    return {"auth_url": sp_oauth.get_authorize_url()}

@router.get("/callback", include_in_schema=False)
def spotify_callback(code: str):
    sp_oauth.get_access_token(code)
    return {"message": "Spotify successfully connected! You can close this window and return to the app."}

# --- 2. Playback State ---
@router.get("/playback")
def get_playback_state(court_id: int = None):
    try:
        sp = get_spotify_client()
        playback = sp.current_playback()
        
        if not playback or not playback.get('item'):
            return {"is_playing": False, "track": None, "device": None, "shuffle": False, "repeat": "off"}
            
        item = playback['item']
        device = playback['device']
        
        return {
            "is_playing": playback['is_playing'],
            "shuffle": playback.get('shuffle_state', False),
            "repeat": playback.get('repeat_state', 'off'),
            "device": {
                "device_id": device['id'],
                "name": device['name'],
                "type": device['type'],
                "is_active": device['is_active'],
                "volume_percent": device['volume_percent']
            } if device else None,
            "track": {
                "track_id": item['id'],
                "title": item['name'],
                "artist": ", ".join([a['name'] for a in item['artists']]),
                "album": item['album']['name'],
                "album_art_url": item['album']['images'][0]['url'] if item['album']['images'] else None,
                "duration_ms": item['duration_ms'],
                "progress_ms": playback['progress_ms'],
                "is_playing": playback['is_playing']
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- 3. Playback Controls ---
class PlayRequest(BaseModel):
    court_id: int = None
    playlist_uri: str = None

@router.post("/play")
def play_music(req: PlayRequest):
    sp = get_spotify_client()
    device_id = get_linked_device_id(req.court_id) 
    
    if req.playlist_uri:
        sp.start_playback(device_id=device_id, context_uri=req.playlist_uri)
    else:
        sp.start_playback(device_id=device_id)
    return {"status": "playing"}

class CourtRequest(BaseModel):
    court_id: int = None

@router.post("/pause")
def pause_music(req: CourtRequest):
    sp = get_spotify_client()
    device_id = get_linked_device_id(req.court_id)
    sp.pause_playback(device_id=device_id)
    return {"status": "paused"}

@router.post("/next")
def skip_next(req: CourtRequest):
    sp = get_spotify_client()
    device_id = get_linked_device_id(req.court_id)
    sp.next_track(device_id=device_id)
    return {"status": "skipped next"}

@router.post("/previous")
def skip_previous(req: CourtRequest):
    sp = get_spotify_client()
    device_id = get_linked_device_id(req.court_id)
    sp.previous_track(device_id=device_id)
    return {"status": "skipped previous"}

class VolumeRequest(BaseModel):
    court_id: int = None
    volume: int

@router.post("/volume")
def set_volume(req: VolumeRequest):
    sp = get_spotify_client()
    device_id = get_linked_device_id(req.court_id)
    sp.volume(volume_percent=req.volume, device_id=device_id)
    return {"status": "volume set"}

class ShuffleRequest(BaseModel):
    court_id: int = None
    state: bool

@router.post("/shuffle")
def toggle_shuffle(req: ShuffleRequest):
    sp = get_spotify_client()
    device_id = get_linked_device_id(req.court_id)
    sp.shuffle(state=req.state, device_id=device_id)
    return {"status": "shuffle toggled"}

class RepeatRequest(BaseModel):
    court_id: int = None
    state: str

@router.post("/repeat")
def toggle_repeat(req: RepeatRequest):
    sp = get_spotify_client()
    device_id = get_linked_device_id(req.court_id)
    sp.repeat(state=req.state, device_id=device_id)
    return {"status": "repeat toggled"}

# --- 4. Devices & Playlists ---
@router.get("/playlists")
def get_playlists():
    sp = get_spotify_client()
    playlists = sp.current_user_playlists(limit=10)
    result = []
    for pl in playlists.get('items', []):
        result.append({
            "playlist_id": pl['id'],
            "name": pl['name'],
            "description": pl['description'],
            "image_url": pl['images'][0]['url'] if pl['images'] else None,
            "track_count": pl['tracks']['total']
        })
    return {"playlists": result}

@router.get("/devices")
def get_devices():
    sp = get_spotify_client()
    devices = sp.devices()
    result = []
    for d in devices.get('devices', []):
        result.append({
            "device_id": d['id'],
            "name": d['name'],
            "type": d['type'],
            "is_active": d['is_active'],
            "volume_percent": d['volume_percent']
        })
    return {"devices": result}

class LinkDeviceRequest(BaseModel):
    court_id: int
    device_id: str
    device_name: str

@router.post("/link-device")
def link_device(req: LinkDeviceRequest):
    device_mapping[req.court_id] = {'id': req.device_id, 'name': req.device_name}
    return {"status": "device linked", "court_id": req.court_id, "device_name": req.device_name}

# --- YAHAN CHANGE KIYA HAI: Direct SQLite DB Integration ---
@router.get("/court-devices")
def get_court_devices():
    result = []
    db_path = "./app/etl.db"
    
    try:
        # Aapke etl.db se seedha connect ho raha hai
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # 'courts' table se id aur name utha raha hai
        # NOTE: Agar aapki DB table ka naam sirf 'court' hai, toh 'courts' ko 'court' kar dena
        cursor.execute("SELECT id, name FROM courts") 
        courts_data = cursor.fetchall()
        conn.close()

        for c in courts_data:
            c_id = c['id']
            c_name = c['name']
            linked_data = device_mapping.get(c_id)
            
            result.append({
                "court_id": c_id,
                "court_name": c_name,
                "device_id": linked_data['id'] if linked_data else None,
                "device_name": linked_data['name'] if linked_data else None,
                "is_linked": linked_data is not None
            })
        return {"court_devices": result}
        
    except Exception as e:
        print(f"DATABASE ERROR: {e}")
        # Agar table ka naam match nahi hua, toh backend break nahi hoga
        return {"court_devices": [
            {"court_id": 1, "court_name": "Database Fetch Error", "device_id": None, "device_name": None, "is_linked": False}
        ]}