FROM python:3.12-slim AS builder

WORKDIR /app

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim

ENV PATH="/opt/venv/bin:$PATH"

RUN useradd -m appuser
WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app ./app

EXPOSE 8000
USER appuser

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
