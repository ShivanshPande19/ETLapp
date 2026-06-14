from app.database import engine, Base

# Sirf nayi table wale model ko import karna zaroori hai taaki SQLAlchemy ko pata chale
from app.models.attendance import Attendance 

# Ye command sirf NAYI tables banayegi, purani tables aur unka data 100% safe rahega
Base.metadata.create_all(bind=engine)

print("✅ Attendance table safely created without touching old data!")