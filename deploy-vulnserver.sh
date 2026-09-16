#!/bin/bash
set -euo pipefail

HOST="0.0.0.0"
ADMIN_USER="admin"
ADMIN_PASS="password"
BASE_URL="http://127.0.0.1:80"

echo "[1/6] Updating system packages"
apt-get update -y && apt-get upgrade -y

echo "[2/6] Installing Docker"
apt-get install -y docker.io
systemctl enable --now docker

wait_http() {
  local url="$1" name="$2" attempts="${3:-30}"
  for i in $(seq 1 "${attempts}"); do
    if curl -sf -o /dev/null "${url}"; then
      echo "  ${name} reachable at ${url}"
      return 0
    fi
    sleep 2
  done
  echo "ERROR: ${name} did not become reachable at ${url}" >&2
  return 1
}

echo "[3/6] Deploying DVWA (port 80)"
docker pull vulnerables/web-dvwa
docker rm -f dvwa 2>/dev/null || true
docker run -d --name dvwa -p "${HOST}:80:80" vulnerables/web-dvwa
wait_http "${BASE_URL}/login.php" "DVWA"

COOKIE_JAR="/tmp/dvwa_cookies.txt"
rm -f "${COOKIE_JAR}"
curl -s -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" "${BASE_URL}/login.php" > /dev/null
curl -s -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -d "username=${ADMIN_USER}&password=${ADMIN_PASS}&Login=Login" "${BASE_URL}/login.php" > /dev/null
curl -s -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -d "create_db=Create / Reset Database" "${BASE_URL}/setup.php" > /dev/null
curl -s -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -d "security=low&seclev_submit=Submit" "${BASE_URL}/security.php" > /dev/null
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/login.php")
if [ "${HTTP_CODE}" = "200" ]; then
  echo "  DVWA up at http://${HOST}:80/ (login: ${ADMIN_USER}/${ADMIN_PASS}, security: low)"
else
  echo "ERROR: DVWA returned HTTP ${HTTP_CODE}" >&2
  exit 1
fi

echo "[4/6] Deploying OWASP Juice Shop (port 3000)"
docker pull bkimminich/juice-shop
docker rm -f juiceshop 2>/dev/null || true
docker run -d --name juiceshop -p "${HOST}:3000:3000" bkimminich/juice-shop
wait_http "http://127.0.0.1:3000/" "Juice Shop"
echo "  Juice Shop up at http://${HOST}:3000/"

echo "[5/6] Deploying bWAPP (port 8080)"
docker pull raesene/bwapp
docker rm -f bwapp 2>/dev/null || true
docker run -d --name bwapp -p "${HOST}:8080:80" raesene/bwapp
wait_http "http://127.0.0.1:8080/install.php" "bWAPP"
curl -s "http://127.0.0.1:8080/install.php?create_db=yes" > /dev/null || true
sleep 2
if curl -sf -o /dev/null "http://127.0.0.1:8080/login.php"; then
  echo "  bWAPP up at http://${HOST}:8080/ (login: bee/bug)"
else
  echo "  NOTE: bWAPP DB init may need manual step — open http://${HOST}:8080/install.php in a browser and click install"
fi

echo "[6/6] Deploying Mutillidae (port 8081)"
docker pull webpwnized/mutillidae
docker rm -f mutillidae 2>/dev/null || true
docker run -d --name mutillidae -p "${HOST}:8081:80" webpwnized/mutillidae
wait_http "http://127.0.0.1:8081/index.php" "Mutillidae"
echo "  Mutillidae up at http://${HOST}:8081/ (login: admin@example.com/admin)"

echo ""
echo "=== Deployment summary ==="
echo "DVWA         http://${HOST}:80/      (admin/password)"
echo "Juice Shop   http://${HOST}:3000/    (no login needed)"
echo "bWAPP        http://${HOST}:8080/    (bee/bug)"
echo "Mutillidae   http://${HOST}:8081/    (admin@example.com/admin)"
echo "SUCCESS: all vulnerable apps deployed"