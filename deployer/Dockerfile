FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    docker-compose \
    jq \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir flask

COPY app.py /app/app.py

WORKDIR /app

EXPOSE 5000

CMD ["python", "app.py"]
