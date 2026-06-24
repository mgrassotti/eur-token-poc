FROM python:3.12-slim-bookworm

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV DATA_ROOT=/data/wallets
ENV PORT=3030

EXPOSE 3030

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "3030"]
