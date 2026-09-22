# Build context is the app root, so the image carries the CLI and the catalog
# too — nothing from the install dir has to be mounted into the container.
FROM python:3.13-alpine

RUN apk add --no-cache docker-cli docker-cli-compose bash curl

WORKDIR /app
COPY VERSION compose.yml compose.linux.yml ./
COPY bin ./bin
COPY catalog ./catalog
COPY console ./console

ENV PYTHONDONTWRITEBYTECODE=1 \
    INFRAPACK_APP=/app \
    INFRAPACK_IN_CONTAINER=1 \
    CONSOLE_INTERNAL_PORT=8000 \
    PATH="/app/bin:${PATH}"
EXPOSE 8000
CMD ["python3", "-u", "/app/console/app.py"]
