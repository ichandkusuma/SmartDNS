
<div align="center">

<img src="docs/images/banner.png" width="100%">

# SmartDNS

### High Performance Recursive DNS Platform powered by **Unbound** and **dnsdist**

Developed and maintained by <a href="https://mynoc.id/" target="_blank">**MyNOC.ID**</a>

![Version](https://img.shields.io/badge/version-v1.0.0-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04_LTS-E95420)
![Debian](https://img.shields.io/badge/Debian-12-A81D33)
![License](https://img.shields.io/github/license/ichandkusuma/SmartDNS)
![Status](https://img.shields.io/badge/status-stable-success)

</div>

---

# About

SmartDNS is an automated DNS Resolver Platform designed for **ISP**, **Enterprise**, **VPS**, and **Self-Hosted** environments.

Built around **Unbound** and **dnsdist**, SmartDNS automatically detects server hardware, calculates optimal performance settings, deploys a production-ready recursive DNS resolver, and configures supporting services with minimal user interaction.

Starting from **v1.0.0**, SmartDNS also includes built-in telemetry and heartbeat monitoring to help manage installations and software versions.

---

# Features

## Smart Installer

- One Command Installation
- Automatic Hardware Detection
- Smart CPU & RAM Tuning
- Recursive DNS Resolver (Unbound)
- High Performance DNS Load Balancer (dnsdist)
- DNSSEC Validation
- DNS Packet Cache
- IPv4 & IPv6 Support
- DNS Blocklist (TrustPositif)
- Domain Whitelist
- Domain Insecure Support
- DNSDist Web Management
- Automatic Blocklist Update
- Automatic Health Check
- Automatic Timezone Configuration
- Automatic Hostname Configuration
- Smart Scheduler (Cron)
- Interactive Installation Wizard

## Monitoring

- Automatic Heartbeat (Every 5 Minutes)
- Built-in Telemetry
- Monitoring Dashboard
- Node Inventory
- Statistics Dashboard

---

# Minimum Requirements

| Component | Minimum |
|-----------|---------:|
| CPU | 2 Core |
| RAM | 2 GB |
| Storage | 10 GB SSD |
| Network | Public IPv4 |
| Root Access | Required |

---

# Recommended Requirements

| Component | Recommended |
|-----------|-------------|
| CPU | 4 Core or Higher |
| RAM | 4 GB or Higher |
| Storage | 15 GB SSD or Higher |
| Network | IPv4 + IPv6 |
| OS | Ubuntu 22.04 LTS / Debian 12 |

---

# Supported Operating Systems

- ✅ Ubuntu 22.04 LTS
- ✅ Debian 12
- ⚠ Ubuntu 24.04 LTS (Experimental)

---

# Installation

```bash
git clone https://github.com/ichandkusuma/SmartDNS.git

cd SmartDNS

bash install.sh
```

---

# Updating SmartDNS

Updating uses the same installer.

```bash
cd SmartDNS

git pull

bash install.sh
```

Existing installations are automatically upgraded while preserving:

- UUID
- Telemetry Data
- Runtime Information
- Existing Configuration
- Scheduler

---

# Installation Wizard

The installer automatically configures:

- Hostname
- Resolve Host
- Timezone
- CPU Threads
- Cache Size
- DNSSEC
- IPv6
- Packet Cache
- DNSDist Web Password
- DNSDist API Key
- Recursive Port
- Frontend Port
- Spoof IPv4
- Spoof IPv6
- Resolver ACL
- UUID
- Heartbeat Registration

---

# Default Service Ports

| Service | Port |
|---------|----:|
| DNS Resolver | 53 |
| Recursive Resolver | 5300 |
| DNSDist Web UI | 8083 |

---

# DNS Features

- DNSSEC Validation
- Recursive Resolver
- DNS Cache
- IPv4 & IPv6 Support
- DNS Blocklist
- Domain Whitelist
- Domain Insecure
- DNSDist Web UI

---

# Automatic Scheduler

| Task | Schedule |
|------|----------|
| Heartbeat | Every 5 Minutes |
| Blocklist Update | Daily |

---

# Generated Automatically

During installation SmartDNS automatically generates:

- UUID
- DNSDist Secret Key
- DNSDist API Key
- DNSDist Web Password
- Optimized Cache Size
- Optimized Thread Count
- Resolver ACL
- Installation Metadata

---

# Project Structure

```text
SmartDNS/
├── cache/
├── data/
├── docs/
├── engine/
├── lib/
├── output/
├── scripts/
├── templates/
├── VERSION
├── install.sh
└── README.md
```

---

# Useful Commands

Restart services

```bash
systemctl restart unbound
systemctl restart dnsdist
```

Check status

```bash
systemctl status unbound
systemctl status dnsdist
```

Test DNS

```bash
dig @127.0.0.1 google.com
dig @::1 google.com
```

Check configuration

```bash
unbound-checkconf
dnsdist --check-config
```

Manual Heartbeat

```bash
/usr/local/bin/smartdns-heartbeat
```

View Installation Metadata

```bash
cat /var/lib/smartdns/install.json
```

View Installation Path

```bash
cat /var/lib/smartdns/install.env
```

View Dnsdist Web Password

```bash
cat cache/secret.env
```

View Cron

```bash
cat /etc/cron.d/smartdns
cat /etc/cron.d/smartdns-heartbeat
```

---

# Telemetry

SmartDNS automatically sends a heartbeat every **5 minutes**.

Collected information:

- Version
- UUID
- Operating System
- CPU
- Memory
- DNSSEC Status
- IPv6 Status
- Query Log Status
- Smart Tuning
- First Seen
- Last Seen

SmartDNS **does not collect** DNS queries, customer traffic, resolver cache, or personal information.

---

# Changelog

See **CHANGELOG.md**

---

# License

MIT License

Presented by **MyNOC.ID**

https://mynoc.id

---

# Disclaimer

SmartDNS is intended for educational, laboratory, enterprise, ISP, and self-hosted DNS environments.

Always validate configurations in your own environment before deploying to production.

---

<div align="center">

### ⭐ If SmartDNS helps your infrastructure, please consider giving this repository a Star.

Made with ❤️ in Indonesia by <a href="https://mynoc.id/" target="_blank">**MyNOC.ID**</a>

</div>
