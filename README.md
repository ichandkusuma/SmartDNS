<div align="center">

<img src="docs/images/banner.png" width="100%">

# SmartDNS

### Automated DNS Resolver Platform for ISP & Enterprise Networks

**Powered by Unbound + dnsdist**

Developed and maintained by **MyNOC.ID**

<br>

![Version](https://img.shields.io/badge/Version-v1.0.0-2563eb)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20LTS-E95420)
![Debian](https://img.shields.io/badge/Debian-12-A81D33)
![Build](https://img.shields.io/badge/Build-Stable-success)
![License](https://img.shields.io/github/license/ichandkusuma/SmartDNS)
![Stars](https://img.shields.io/github/stars/ichandkusuma/SmartDNS?style=social)

</div>

---

# Why SmartDNS?

Deploying a recursive DNS resolver is often repetitive, time-consuming, and requires extensive manual tuning.

**SmartDNS** automates the entire deployment process—from hardware detection and performance tuning to security hardening and monitoring—allowing administrators to deploy production-ready DNS resolvers in minutes.

Designed for:

- 🌐 Internet Service Providers (ISP)
- 🏢 Enterprise Networks
- 🖥 Data Centers
- 🌍 Network Operators

---

# Features

## 🚀 Smart Installer

- Automatic Hardware Detection
- Automatic Operating System Detection
- Automatic CPU Detection
- Automatic Memory Detection
- Automatic Network Detection
- Automatic Internet Detection
- Automatic Kernel Detection
- Automatic Hostname Detection
- Automatic Virtualization Detection
- Automatic Uptime Detection

---

## ⚡ Smart Auto Tuning

Automatically optimizes:

### Unbound

- Threads
- RRSET Cache
- Message Cache
- Slabs
- Infra Cache
- Outgoing Range
- Num Queries

### dnsdist

- Packet Cache
- TCP Threads
- TCP Queue
- UDP Outstanding

No manual calculation required.

---

## 🔒 Security

- DNSSEC
- Rate Limiting
- ACL Generator
- Security Hardening
- Sysctl Optimization
- Swap Optimization

---

## 🛡 DNS Features

- IPv6 Ready
- Blocklist Support
- Query Logging
- dnsdist Web API

---

## 📡 Built-in Monitoring

Starting from **v1.0.0**, SmartDNS includes a lightweight telemetry platform.

Features include:

- Automatic Heartbeat
- Version Tracking
- Deployment Monitoring
- Node Inventory
- Statistics
- Online / Offline Status

---

# Supported Operating Systems

| Distribution | Status |
|--------------|--------|
| Ubuntu 22.04 LTS | ✅ Supported |
| Debian 12 | ✅ Supported |
| Ubuntu 24.04 LTS | ⚠ Experimental |

---

# Minimum Requirements

| Component | Requirement |
|-----------|------------:|
| CPU | 2 Core |
| RAM | 2 GB |
| Storage | 20 GB |
| Internet | Required |

---

# Installation

Clone the repository.

```bash
git clone https://github.com/ichandkusuma/SmartDNS.git

cd SmartDNS

bash install.sh
```

That's it.

SmartDNS automatically performs:

- Hardware Detection
- Smart Auto Tuning
- Runtime Builder
- ACL Generation
- Security Hardening
- Blocklist Installation
- Service Validation
- Automatic Heartbeat Registration

---

# Updating

Updating SmartDNS uses the same installer.

```bash
cd SmartDNS

git pull

bash install.sh
```

The installer automatically:

- Detects existing installation
- Preserves UUID
- Preserves telemetry data
- Preserves runtime information
- Updates SmartDNS components
- Updates templates
- Updates scheduler

No manual migration is required.

---

# Installation Modes

### Fresh Installation

Performs a complete installation.

### Upgrade

Automatically upgrades SmartDNS while preserving:

- UUID
- Runtime Information
- Telemetry Data
- Existing Configuration

---

# Architecture

```

+-------------------+

| SmartDNS Node |

+---------+---------+

|

Heartbeat

(JSON)

|

v

+-------------------+

| Telemetry API |

+---------+---------+

|

v

+-------------------+

| JSON Storage |

+---------+---------+

|

v

+-------------------+

| Monitoring |

| Dashboard |

+-------------------+

```

---

# Project Structure

```

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

└── install.sh

```

---

# Runtime Files

SmartDNS stores runtime information in:

```

/var/lib/smartdns/

├── uuid

├── install.json

└── install.env

```

These files are automatically created during installation and preserved during upgrades.

---

# Privacy

SmartDNS **does not collect**:

- DNS Queries
- Client Requests
- Resolver Cache
- Customer Traffic
- Personal Information

Telemetry is used only for:

- Version Statistics
- Compatibility
- Installation Monitoring
- Deployment Statistics

---

# Roadmap

## Current Release

- ✅ Smart Installer
- ✅ Smart Auto Tuning
- ✅ Hardware Detection
- ✅ Runtime Builder
- ✅ ACL Generator
- ✅ Security Hardening
- ✅ DNS Blocklist
- ✅ Scheduler
- ✅ Automatic Heartbeat
- ✅ Telemetry
- ✅ Monitoring Dashboard
- ✅ Node Inventory
- ✅ Statistics

---

## Next Release

- SmartDNS CLI
- Update Checker
- Automatic Update
- Release Channel

---

# Changelog

See [CHANGELOG.md](CHANGELOG.md)

---

# License

This project is licensed under the MIT License.

---

# Developed By

## MyNOC.ID

**Network • Automation • Monitoring**

Founder & Lead Developer

**iChand Kusuma**

🌐 https://mynoc.id

🐙 https://github.com/ichandkusuma

---

<div align="center">

### ⭐ If SmartDNS helps your infrastructure, please consider giving this repository a Star.

Made with ❤️ in Indonesia by **MyNOC.ID**

</div>
