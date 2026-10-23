FROM python:3.12-slim-bookworm
WORKDIR /app
COPY solver/requirements.txt /app/solver/requirements.txt
COPY solver/staging/requirements.txt /app/solver/staging/requirements.txt
RUN pip install --no-cache-dir -r /app/solver/staging/requirements.txt \
    && groupadd --system capacity && useradd --system --gid capacity capacity
COPY solver/cargo_capacity.py /app/solver/cargo_capacity.py
COPY solver/staging/service.py solver/staging/worker.py /app/solver/staging/
COPY solver/reference /app/solver/reference
COPY solver/staging/timed_offer.sql /app/solver/staging/timed_offer.sql
COPY solver/verification/a350-v2-seven-scenarios-2026-10-23/final/inputs /app/solver/verification/a350-v2-seven-scenarios-2026-10-23/final/inputs
COPY solver/verification/a350-v2-seven-scenarios-2026-10-23/final/results.json /app/solver/verification/a350-v2-seven-scenarios-2026-10-23/final/results.json
ENV PORT=8080 PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
USER capacity
EXPOSE 8080
CMD ["python", "solver/staging/service.py"]
