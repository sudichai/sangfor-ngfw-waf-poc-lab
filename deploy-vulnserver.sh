#!/bin/bash
set -euo pipefail

DVWA_HOST="0.0.0.0"
DVWA_PORT="80"
ADMIN_USER="admin"
ADMIN_PASS="password"
BASE_URL="http://127.0.0.1:${DVWA_PORT}"

echo "[1/5] Updating system packages"
apt-get update -y && apt-get upgrade -y

echo "[2/5] Installing Docker"
apt-get install -y docker.io
systemctl enable --now docker

echo "[3/5] Pulling and starting DVWA container"
docker pull vulnerables/web-dvwa
docker rm -f dvwa 2>/dev/null || true
docker run -d --name dvwa -p "${DVWA_HOST}:${DVWA_PORT}:80" vulnerables/web-dvwa

echo "[4/5] Waiting for DVWA to become reachable"
for i in $(seq 1 30); do
  if curl -sf -o /dev/null "${BASE_URL}/login.php"; then
    break
  fi
  sleep 2
done

COOKIE_JAR="/tmp/dvwa_cookies.txt"
rm -f "${COOKIE_JAR}"

echo "[5/5] Initializing DVWA database and setting security level"
curl -s -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" "${BASE_URL}/login.php" > /dev/null
curl -s -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -d "username=${ADMIN_USER}&password=${ADMIN_PASS}&Login=Login" "${BASE_URL}/login.php" > /dev/null
curl -s -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -d "create_db=Create / Reset Database" "${BASE_URL}/setup.php" > /dev/null
curl -s -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -d "security=low&seclev_submit=Submit" "${BASE_URL}/security.php" > /dev/null

echo "Verifying DVWA responds on port ${DVWA_PORT}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/login.php")
if [ "${HTTP_CODE}" = "200" ]; then
  echo "SUCCESS: DVWA is up at http://${DVWA_HOST}:${DVWA_PORT}/ (login: ${ADMIN_USER}/${ADMIN_PASS}, security level: low)"
else
  echo "ERROR: DVWA returned HTTP ${HTTP_CODE}"
  exit 1
fi