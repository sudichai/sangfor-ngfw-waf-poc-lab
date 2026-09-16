# Deployment Guide — Sangfor NGFW + WAF POC Lab on HCI

Follow these steps in order. Reference IPs from the design doc (`Sangfor-NGFW-WAF-POC-LAB-Design-2026-09-16.md`).

## 1. Prerequisites

| Item | Detail |
|------|--------|
| Sangfor HCI cluster | Running, with network pools for the 4 zones |
| Ubuntu 24.04 LTS ISO | For vuln server + client VM |
| Kali Linux ISO or OVA | Latest Rolling release |
| Sangfor NGFW OVA | vNGAF image for HCI |
| Tools | curl (host), SSH client, browser for NGFW GUI |

## 2. Network Zones on HCI

Create 4 networks (VLAN or flat pools) and note their names:

| HCI Network | Zone | Subnet | Used By |
|-------------|------|--------|---------|
| net-wan | WAN | 10.0.0.0/24 | Kali |
| net-vuln | VULNSERVER | 192.168.20.0/24 | DVWA server |
| net-lan | LAN | 192.168.10.0/24 | Client VM |
| net-mgmt | MGMT | 172.16.1.0/24 | NGFW management |

## 3. Deploy NGFW (vNGAF)

1. Import the NGFW OVA into HCI.
2. Attach 4 vNICs: one per zone network (net-wan, net-vuln, net-lan, net-mgmt).
3. Boot, complete initial setup via console:
   - MGMT IP `172.16.1.1/24`
   - WAN IP `10.0.0.1/24`
   - DMZ IP `192.168.20.1/24`
   - LAN IP `192.168.10.1/24`
4. Log into NGFW GUI from a machine in net-mgmt (browser).
5. Configure zones, security policies, WAF/IPS enable, and DNAT per section 4 of the design doc.

## 4. Deploy Vuln Server (DVWA)

1. Create Ubuntu 24.04 VM on HCI: 2 vCPU, 4 GB RAM, 40 GB disk.
2. Attach vNIC to **net-vuln**.
3. Install Ubuntu (server, minimal), set static IP:
   - IP `192.168.20.10/24`, GW `192.168.20.1`, DNS optional
4. SSH in and get the script from the public GitHub repo (no file upload needed):

Option A — git clone:

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/sudichai/sangfor-ngfw-waf-poc-lab.git
cd sangfor-ngfw-waf-poc-lab
sudo bash deploy-vulnserver.sh
```

Option B — curl the script directly (no git install):

```bash
curl -O https://raw.githubusercontent.com/sudichai/sangfor-ngfw-waf-poc-lab/master/deploy-vulnserver.sh
sudo bash deploy-vulnserver.sh
```

Note: the VM needs internet access (through HCI NAT/proxy) to reach GitHub and to pull the Docker image.

5. Verify: `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/login.php` → `200`

## 5. Deploy Attacker (Kali)

1. Create Kali VM on HCI: 2 vCPU, 4 GB RAM, 60 GB disk.
2. Attach vNIC to **net-wan**.
3. Install Kali (ISO or import OVA), set static IP:
   - IP `10.0.0.10/24`, GW `10.0.0.1`, DNS optional
4. Run:

```bash
sudo bash deploy-kali-prep.sh
```

5. Verify Kali can reach the NGFW public IP: `ping 10.0.0.1`, `curl -I http://10.0.0.1/`

## 6. Deploy Client VM (Sanity Check)

1. Create Ubuntu 24.04 VM (desktop) on HCI: 2 vCPU, 4 GB RAM, 40 GB disk.
2. Attach vNIC to **net-lan**.
3. Set static IP `192.168.10.10/24`, GW `192.168.10.1`.
4. Open browser → `http://10.0.0.1/` → DVWA login page should load (via DNAT).

## 7. Connectivity Test Matrix

| From | To | Path | Expected |
|------|----|------|----------|
| Kali | NGFW WAN (10.0.0.1) | ping / curl :80 | Reachable, DNAT → DVWA |
| Client | NGFW WAN (10.0.0.1) | browser :80 | DVWA login page |
| Kali | DVWA direct (192.168.20.10) | ping | Blocked (no route / policy) |

## 8. Run the Tests

Follow the test matrix in the design doc, phase by phase:

1. Phase 1: recon from Kali (nmap).
2. Phase 2: web attacks (sqlmap, curl, Burp).
3. Phase 3: brute force (hydra).
4. Phase 4: reverse shell (if upload succeeds).
5. Phase 5: sanity check from client VM.

Capture NGFW WAF/IPS logs + Kali output for every test (evidence checklist, design doc section 6).

## 9. Reset / Clean Up

- Reset DVWA to a clean state: `sudo docker rm -f dvwa && sudo bash deploy-vulnserver.sh`
- Snapshot all 3 VMs on HCI before the first test run — restore instead of reconfiguring.