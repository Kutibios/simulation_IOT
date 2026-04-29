FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY subscriber.py .
COPY dashboard.py .
RUN mkdir -p /data
CMD ["sh", "-c", "python subscriber.py & python dashboard.py"]
