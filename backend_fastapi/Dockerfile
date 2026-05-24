# Use official Python lightweight image
FROM python:3.10-slim

# Set the working directory inside the container
WORKDIR /code

# Copy requirements file first (for better caching)
# Ab hum 'backend_fastapi/' prefix nahi lagayenge
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code and your seed_etl.db
# 'COPY . .' ka matlab hai saara current data uthao aur container mein daal do
COPY . .

# Ensure the runtime dynamic port expansion works perfectly
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port $PORT"]