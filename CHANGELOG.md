# Changelog

All notable changes to SmartDNS are documented in this file.

## [1.0.4] - 2026-11-18

### Added
- Multi fallback support for blocklist sources.
- Gzip blocklist source support.
- Plaintext blocklist fallback support.
- Sequential fallback processing.

### Improved
- Blocklist updater resilience when the primary source is unavailable.
- Fallback processing now stops after the first successful source.

## [1.0.3] - 2026-10-11

### Added
- SmartDNS Management Web UI on port 5000.
- System overview and service status monitoring.
- Real-time monitoring for CPU, RAM, swap, disk usage, disk I/O/wait, network RX/TX, and PPS.
- Domain blocklist search.
- DNSDist and Unbound configuration management supported by the UI.
- Blocklist source overview and active service monitoring.
- Live DNS analytics and query logs.
- DNS resolution test suite.
- Tools and maintenance features, including Patch Update.
- Local UI installer with systemd service integration.
- SmartDNS Management UI installation during initial installation and patch updates.

### Fixed
- DNSDist console output filtering for known plain-text password warnings during cache flush operations.
- Dynamic version detection from the repository VERSION file.
- SmartDNS repository path detection for UI deployments.

### Documentation
- Added SmartDNS Management Web UI documentation in Indonesian and English.
- Documented the Web UI address, login credentials, and port 5000.

## [1.0.2]

- Previous release. See the Git history for detailed changes.
