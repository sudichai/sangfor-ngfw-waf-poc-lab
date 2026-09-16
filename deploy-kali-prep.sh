#!/bin/bash
set -euo pipefail

echo "[1/4] Updating package lists"
apt-get update -y

echo "[2/4] Installing / verifying attacker tools"
apt-get install -y nmap sqlmap burpsuite hydra metasploit-framework netcat-traditional gobuster nikto curl

echo "[3/4] Creating lab workspace"
mkdir -p /root/lab
cat > /root/lab/reverse-shell-listener.sh << 'EOF'
#!/bin/bash
exec nc -lvnp "${1:-4444}"
EOF
chmod +x /root/lab/reverse-shell-listener.sh

echo "[4/4] Verifying tools"
for tool in nmap sqlmap burpsuite hydra msfconsole nc gobuster nikto; do
  if command -v "${tool}" > /dev/null 2>&1; then
    echo "OK: ${tool}"
  else
    echo "MISSING: ${tool}"
  fi
done

echo "SUCCESS: Kali is ready. Listener helper: /root/lab/reverse-shell-listener.sh [port]"