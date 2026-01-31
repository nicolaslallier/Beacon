FROM python:3.12-slim AS builder

ENV VENV_PATH=/opt/venv
WORKDIR /build

RUN python -m venv "${VENV_PATH}"
ENV PATH="${VENV_PATH}/bin:${PATH}"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim

ENV VENV_PATH=/opt/venv
ENV PATH="${VENV_PATH}/bin:${PATH}"
WORKDIR /app

RUN useradd --create-home appuser
COPY --from=builder "${VENV_PATH}" "${VENV_PATH}"
COPY app /app/app

USER appuser
EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
