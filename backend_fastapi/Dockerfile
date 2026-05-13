FROM python:3.11-slim

WORKDIR /backend_fastapi

# Copy requirements first (cache layer)
COPY backend_fastapi/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy entire backend folder
COPY backend_fastapi/ .

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
