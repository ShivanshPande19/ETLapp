FROM python:3.11-slim

WORKDIR /backend_fastapi

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy entire backend
COPY . .

# Expose port
EXPOSE 8000

# Start server — entrypoint is app/main.py → app object
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
