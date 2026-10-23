#!/usr/bin/env bash
# Starts the image together with MariaDB, waits for the fresh install and checks
# that the admin can log in. Used by CI before an image is published.
#
# Usage: tests/smoke-test.sh <image>
set -Eeuo pipefail

IMAGE="${1:?Usage: $0 <image>}"
NAME="rs-smoke-$$"
NET="${NAME}-net"
PORT="${SMOKE_PORT:-18080}"
DB_PW="smoke-db-password"
ADMIN_PW="Smoke-Test-Passw0rd!"

cleanup() {
  status=$?
  if (( status != 0 )); then
    echo "---- ResourceSpace log ----"; docker logs "${NAME}-rs" 2>&1 | tail -n 100 || true
    echo "---- MariaDB log ----";       docker logs "${NAME}-db" 2>&1 | tail -n 30 || true
  fi
  docker rm -f "${NAME}-rs" "${NAME}-db" >/dev/null 2>&1 || true
  docker volume rm "${NAME}-data" >/dev/null 2>&1 || true
  docker network rm "${NET}" >/dev/null 2>&1 || true
  exit "${status}"
}
trap cleanup EXIT

docker network create "${NET}" >/dev/null
docker volume create "${NAME}-data" >/dev/null

docker run -d --name "${NAME}-db" --network "${NET}" --network-alias mariadb \
  -e MARIADB_RANDOM_ROOT_PASSWORD=1 \
  -e MARIADB_DATABASE=resourcespace \
  -e MARIADB_USER=resourcespace \
  -e MARIADB_PASSWORD="${DB_PW}" \
  mariadb:11.4 >/dev/null

docker run -d --name "${NAME}-rs" --network "${NET}" -p "127.0.0.1:${PORT}:80" \
  -v "${NAME}-data:/data" \
  -e RS_BASEURL="http://localhost:${PORT}" \
  -e RS_DB_PASSWORD="${DB_PW}" \
  -e RS_SCRAMBLE_KEY="$(openssl rand -hex 32)" \
  -e RS_API_SCRAMBLE_KEY="$(openssl rand -hex 32)" \
  -e RS_ADMIN_PASSWORD="${ADMIN_PW}" \
  -e RS_ADMIN_EMAIL="admin@example.com" \
  -e RS_WAIT_FOR_SYNC=false \
  "${IMAGE}" >/dev/null

echo "Warte auf ResourceSpace ..."
for _ in $(seq 1 90); do
  if curl -fsS -o /dev/null "http://localhost:${PORT}/login.php"; then
    break
  fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "${NAME}-rs")" != "true" ]]; then
    echo "Container wurde beendet." >&2; exit 1
  fi
  sleep 5
done
curl -fsS -o /dev/null "http://localhost:${PORT}/login.php"

echo "Prüfe Admin-Login ..."
headers="$(curl -sS -o /dev/null -D - \
  -H "Origin: http://localhost:${PORT}" \
  --data-urlencode "username=admin" \
  --data-urlencode "password=${ADMIN_PW}" \
  --data-urlencode "Submit=Login" \
  "http://localhost:${PORT}/login.php")"
if ! grep -qiE '^set-cookie: user=[0-9a-f]{16,}' <<<"${headers}"; then
  echo "${headers}" >&2
  echo "Login fehlgeschlagen: kein Session-Cookie." >&2
  exit 1
fi

echo "Prüfe Datenbank-Dump ..."
docker exec "${NAME}-rs" test -s /data/db-dump/resourcespace.sql.gz

echo "Prüfe Wiederherstellung aus Dump ..."
docker exec "${NAME}-db" sh -c \
  "mariadb -uresourcespace -p'${DB_PW}' -e 'DROP DATABASE resourcespace; CREATE DATABASE resourcespace;'"
docker restart "${NAME}-rs" >/dev/null
for _ in $(seq 1 60); do
  curl -fsS -o /dev/null "http://localhost:${PORT}/login.php" && break
  sleep 5
done
docker logs "${NAME}-rs" 2>&1 | grep -q "Wiederherstellung abgeschlossen" \
  || { echo "Wiederherstellung wurde nicht ausgeführt." >&2; exit 1; }
headers="$(curl -sS -o /dev/null -D - \
  -H "Origin: http://localhost:${PORT}" \
  --data-urlencode "username=admin" \
  --data-urlencode "password=${ADMIN_PW}" \
  --data-urlencode "Submit=Login" \
  "http://localhost:${PORT}/login.php")"
grep -qiE '^set-cookie: user=[0-9a-f]{16,}' <<<"${headers}" \
  || { echo "Login nach Wiederherstellung fehlgeschlagen." >&2; exit 1; }

echo "Smoke-Test erfolgreich."
