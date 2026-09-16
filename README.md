# Sangfor NGFW + WAF POC Lab

Customer POC lab materials — demonstrating that Sangfor NGFW (built-in WAF module + IPS + App Control) detects and blocks OWASP web attacks and network-level attacks launched from Kali against 4 vulnerable web apps: DVWA, OWASP Juice Shop, bWAPP, and Mutillidae.

## Topology

4 zones, 100% virtual on Sangfor HCI:

| Zone | Network | Device |
|------|---------|--------|
| WAN | 10.0.0.0/24 | Kali (attacker) 10.0.0.10 |
| VULNSERVER | 192.168.20.0/24 | Ubuntu 24.04 (DVWA :80, Juice Shop :3000, bWAPP :8080, Mutillidae :8081) 192.168.20.10 |
| LAN | 192.168.10.0/24 | Client VM (sanity check) 192.168.10.10 |
| MGMT | 172.16.1.0/24 | NGFW management 172.16.1.1 |

Traffic: Kali (WAN) → NGFW public IP 10.0.0.1 (ports :80, :3000, :8080, :8081) → DNAT → targets, all inspected by WAF + IPS.

## Files

| File | Purpose |
|------|---------|
| `Sangfor-NGFW-WAF-POC-LAB-Design-2026-09-16.md` | Full lab design: topology, IP scheme, DNAT table, NGFW config steps, test matrix (8 phases), pass criteria, evidence checklist |
| `deploy-vulnserver.sh` | Ubuntu 24.04: install Docker, run DVWA + Juice Shop + bWAPP + Mutillidae, auto-init DBs, set security level to low |
| `deploy-kali-prep.sh` | Kali: install/verify attack tools (nmap, sqlmap, burpsuite, hydra, metasploit, netcat) + reverse shell listener helper |
| `auto-attack.sh` | One-command automated attack run against all 4 targets — takes only the target public IP as input |
| `README-deploy.md` | Step-by-step deployment on Sangfor HCI (VMs, zones, NGFW config, GitHub-pull method) |

## Quick Start

### 1. Deploy the vuln servers (Ubuntu 24.04 VM — single VM, all apps in Docker)

Pull from this repo (no file upload needed):

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/sudichai/sangfor-ngfw-waf-poc-lab.git
cd sangfor-ngfw-waf-poc-lab
sudo bash deploy-vulnserver.sh
```

This deploys 4 apps on the one VM: DVWA (:80), OWASP Juice Shop (:3000), bWAPP (:8080, bee/bug), Mutillidae (:8081, admin@example.com/admin).

### 2. Prepare the attacker (Kali VM)

```bash
cd sangfor-ngfw-waf-poc-lab
sudo bash deploy-kali-prep.sh
```

### 3. Run the full attack automatically

```bash
sudo bash auto-attack.sh <target-public-ip>
```

Example:

```bash
sudo bash auto-attack.sh 10.0.0.1
```

What it does (per phase): login DVWA → nmap recon → sqlmap SQLi → XSS / LFI / command injection → webshell upload → hydra brute force (top 200 passwords) → reverse shell (auto listener + trigger + connection check) → Juice Shop (SQLi / XSS / default creds) → bWAPP (CMDi / XXE / SQLi / XSS) → Mutillidae (SQLi / CMDi / XSS).

All output is saved to `/root/lab/evidence/<timestamp>/` with a `summary.txt` — use it as evidence alongside NGFW WAF/IPS logs.

Optional tuning:

```bash
TIMEOUT_SECONDS=300 sudo bash auto-attack.sh 10.0.0.1   # longer per-command timeout
LSHELL_PORT=5555 sudo bash auto-attack.sh 10.0.0.1       # different listener port
```

## Test Matrix Overview

| Phase | Attack | Target | Expected NGFW Action |
|-------|--------|--------|----------------------|
| 1 | Port scan / recon | DVWA (all) | IPS scan detection |
| 2 | SQLi, XSS, LFI, CMDi, webshell upload | DVWA | WAF rule hit — blocked |
| 3 | Login brute force | DVWA | WAF login protection / rate limiting |
| 4 | Reverse shell (C2 egress) | DVWA | IPS / App Control flag |
| 5 | SQLi, XSS, default creds | Juice Shop | WAF rule hit — blocked |
| 6 | CMDi, XXE, SQLi, XSS | bWAPP | WAF rule hit — blocked |
| 7 | SQLi, CMDi, XSS | Mutillidae | WAF rule hit — blocked |
| 8 | Legit browsing (LAN client) | DVWA | No blocking (sanity check) |

Full details, IP scheme, and evidence checklist: see `Sangfor-NGFW-WAF-POC-LAB-Design-2026-09-16.md`.

## Lab Use Only

This material is for authorized lab/POC environments. Do not use against systems you do not own or have written permission to test.