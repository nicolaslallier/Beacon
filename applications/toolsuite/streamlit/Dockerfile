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
COPY app.py /app/app.py

USER appuser
EXPOSE 8501

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8501/_stcore/health')"

CMD ["streamlit", "run", "app.py", "--server.address=0.0.0.0", "--server.port=8501"]
