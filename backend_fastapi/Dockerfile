FROM python:3.11-slim

WORKDIR /backend_fastapi

COPY backend_fastapi/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend_fastapi/ .

EXPOSE 8000

# Shell form (not exec form) — taaki $PORT runtime pe expand ho
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port $PORT"]
