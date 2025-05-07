# Dockerfile
FROM python:3.12-slim

# 1) Pick up requirements
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2) Copy your application code
COPY app/ ./

COPY enphase_token.json ./

CMD ["python", "main.py"]
