#!/usr/bin/env python3
"""
SmartDNS Management Web Application
Server backend for managing dnsdist, blocklists, and services.
Zero external dependencies - runs on Python 3.7+ standard library.
"""

import os
import sys
import re
import json
import time
import shutil
import hashlib
import secrets
import subprocess
from datetime import datetime
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

# Base configuration paths
DNSDIST_CONF = "/etc/dnsdist/dnsdist.conf"
UNBOUND_CONF = "/etc/unbound/unbound.conf.d/smartdns.conf"
SOURCES_TXT = "/opt/blocklist/sources.txt"
DOMAINS_TXT = "/opt/blocklist/domains.txt"
UPDATE_SCRIPT = "/opt/blocklist/update-blocklist.sh"
UPDATE_LOG = "/opt/blocklist/update.log"
CONFIG_FILE = "/opt/smartdns-ui/config.json"
STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")

import os
from pathlib import Path

# Repo directory: bisa di-override oleh systemd saat GUI sudah dipasang.
SMARTDNS_DIR = os.environ.get("SMARTDNS_DIR", "").strip()

if not SMARTDNS_DIR:
    # Source repo: ui/server.py -> root directory SmartDNS
    SMARTDNS_DIR = str(Path(__file__).resolve().parent.parent)

SMARTDNS_DIR = str(Path(SMARTDNS_DIR).resolve())

INSTALL_JSON = "/var/lib/smartdns/install.json"
INSTALL_ENV = "/var/lib/smartdns/install.env"
HEARTBEAT_BIN = "/usr/local/bin/smartdns-heartbeat"
MAINTENANCE_LOG = "/opt/smartdns-ui/maintenance.log"

active_tool_update = {
    "running": False,
    "pid": None,
    "type": None,
    "status": "idle",
    "start_time": 0
}

SESSION_FILE = "/opt/smartdns-ui/sessions.json"

def load_sessions():
    if os.path.exists(SESSION_FILE):
        try:
            with open(SESSION_FILE, "r", encoding="utf-8") as f:
                return set(json.load(f))
        except Exception:
            return set()
    return set()

def save_sessions(sessions_set):
    try:
        os.makedirs(os.path.dirname(SESSION_FILE), exist_ok=True)
        with open(SESSION_FILE, "w", encoding="utf-8") as f:
            json.dump(list(sessions_set), f)
    except Exception:
        pass

active_sessions = load_sessions()

def get_dnsdist_web_password():
    # Read the current Web UI password from dnsdist's config file.
    try:
        with open(DNSDIST_CONF, "r", encoding="utf-8") as f:
            content = f.read()
        match = re.search(
            r'setWebserverConfig\s*\(\s*\{[\s\S]*?\bpassword\s*=\s*"([^"]*)"',
            content
        )
        return match.group(1) if match else None
    except (OSError, UnicodeError) as e:
        print(f"[WARN] Unable to read DNSDist Web UI password: {e}")
        return None


def load_app_config():
    default_config = {
        "admin_username": "admin",
        # Authentication is checked against the live DNSDist config.
        "password_hash": "",
        "port": 5000,
        "host": "0.0.0.0"
    }
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
                default_config.update(saved)
        except Exception as e:
            print(f"[WARN] Failed to load config.json: {e}")
    else:
        try:
            os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(default_config, f, indent=2)
        except Exception as e:
            print(f"[WARN] Failed to save default config.json: {e}")

    # Ignore any legacy static password hash in config.json.
    default_config["password_hash"] = ""
    return default_config

APP_CONFIG = load_app_config()

cached_domain_count = {"count": 0, "mtime": 0}
active_update_job = {"running": False, "pid": None, "start_time": 0, "status": "idle"}

def get_blocklist_count():
    global cached_domain_count
    if not os.path.exists(DOMAINS_TXT):
        return 0
    try:
        mtime = os.path.getmtime(DOMAINS_TXT)
        if cached_domain_count.get("mtime") == mtime and cached_domain_count.get("count", 0) > 0:
            return cached_domain_count["count"]
        # Use fast wc -l
        res = subprocess.run(["wc", "-l", DOMAINS_TXT], capture_output=True, text=True, check=True)
        count_str = res.stdout.strip().split()[0]
        count = int(count_str)
        cached_domain_count = {"count": count, "mtime": mtime}
        return count
    except Exception as e:
        print(f"[ERROR] Failed to count domains: {e}")
        return cached_domain_count.get("count", 0) if isinstance(cached_domain_count, dict) else 0

def search_domains(query, limit=100):
    if not os.path.exists(DOMAINS_TXT) or not query.strip():
        return {
            "exact_match": False,
            "matches": [],
            "query": query,
            "total_found": 0,
            "limit_reached": False
        }

    clean_query = query.strip()
    exact_domain = None
    matches = []

    try:
        # Cari exact match secara terpisah agar tidak tertinggal
        # akibat batas hasil substring.
        res_exact = subprocess.run(
            ["grep", "-Fxi", "-m", "1", "--", clean_query, DOMAINS_TXT],
            capture_output=True,
            text=True
        )
        if res_exact.returncode == 0 and res_exact.stdout.strip():
            exact_domain = res_exact.stdout.strip().splitlines()[0].strip()

        # Ambil hasil substring.
        res_match = subprocess.run(
            ["grep", "-Fi", "-m", str(limit), "--", clean_query, DOMAINS_TXT],
            capture_output=True,
            text=True
        )
        if res_match.returncode == 0 and res_match.stdout:
            matches = [
                line.strip()
                for line in res_match.stdout.splitlines()
                if line.strip()
            ]

    except Exception as e:
        print(f"[ERROR] Domain search failed: {e}")

    # Exact match di posisi pertama, lalu substring tanpa duplikat.
    ordered = []
    seen = set()

    if exact_domain:
        ordered.append(exact_domain)
        seen.add(exact_domain.casefold())

    for domain in matches:
        key = domain.casefold()
        if key not in seen:
            ordered.append(domain)
            seen.add(key)

    total_before_limit = len(ordered)
    ordered = ordered[:limit]

    return {
        "exact_match": exact_domain is not None,
        "matches": ordered,
        "query": clean_query,
        "total_found": len(ordered),
        "limit_reached": total_before_limit >= limit
    }

def get_netstat_services():
    services = []
    cmd = ["netstat", "-ntplu"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        output = res.stdout
    except FileNotFoundError:
        # Fallback to ss if netstat not found
        try:
            res = subprocess.run(["ss", "-ntplu"], capture_output=True, text=True)
            output = res.stdout
        except Exception as e:
            return [{"error": f"Failed to execute netstat/ss: {e}"}]

    lines = output.splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith("Active Internet") or line.startswith("Proto") or line.startswith("Netid"):
            continue
        parts = line.split()
        if len(parts) < 6:
            continue
        proto = parts[0]
        # Netstat format:
        # Proto Recv-Q Send-Q Local Address Foreign Address State PID/Program name (tcp)
        # Proto Recv-Q Send-Q Local Address Foreign Address PID/Program name (udp)
        try:
            if proto.startswith("tcp"):
                recv_q = parts[1]
                send_q = parts[2]
                local_addr = parts[3]
                foreign_addr = parts[4]
                state = parts[5]
                pid_prog = " ".join(parts[6:]) if len(parts) >= 7 else "-"
            else: # udp
                recv_q = parts[1]
                send_q = parts[2]
                local_addr = parts[3]
                foreign_addr = parts[4]
                state = "UNCONN"
                pid_prog = " ".join(parts[5:]) if len(parts) >= 6 else "-"

            # Split local IP and Port
            if ":" in local_addr:
                colon_idx = local_addr.rfind(":")
                ip = local_addr[:colon_idx]
                port = local_addr[colon_idx+1:]
            else:
                ip = local_addr
                port = "-"

            # Split PID and program name
            pid = "-"
            prog = "-"
            if "/" in pid_prog:
                pid_split = pid_prog.split("/", 1)
                pid = pid_split[0].strip()
                prog = pid_split[1].strip()
            elif pid_prog != "-":
                prog = pid_prog

            services.append({
                "proto": proto,
                "recv_q": recv_q,
                "send_q": send_q,
                "local_addr": local_addr,
                "ip": ip,
                "port": port,
                "foreign_addr": foreign_addr,
                "state": state,
                "pid": pid,
                "program": prog,
                "raw_pid_prog": pid_prog
            })
        except Exception:
            continue
    return services

def check_service_status(service_name):
    try:
        res = subprocess.run(["systemctl", "is-active", service_name], capture_output=True, text=True)
        return res.stdout.strip() == "active"
    except Exception:
        return False

def test_dnsdist_syntax(config_content):
    tmp_path = f"/tmp/dnsdist_test_{int(time.time()*1000)}.conf"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(config_content)
        res = subprocess.run(
            ["dnsdist", "--check-config", f"--config={tmp_path}"],
            capture_output=True, text=True
        )
        is_ok = res.returncode == 0
        message = (res.stdout + "\n" + res.stderr).strip()
        return is_ok, message
    except Exception as e:
        return False, str(e)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass

def test_unbound_syntax(config_content):
    tmp_path = f"/tmp/unbound_test_{int(time.time()*1000)}.conf"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(config_content)
        res = subprocess.run(
            ["unbound-checkconf", tmp_path],
            capture_output=True, text=True
        )
        is_ok = res.returncode == 0
        message = (res.stdout + "\n" + res.stderr).strip()
        return is_ok, message
    except Exception as e:
        return False, str(e)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass

def sync_acl_to_unbound(final_acls):
    if not os.path.exists(UNBOUND_CONF):
        return False, f"File {UNBOUND_CONF} tidak ditemukan"
    try:
        with open(UNBOUND_CONF, "r", encoding="utf-8") as f:
            content = f.read()

        acl_lines = "\n".join([f"    access-control: {a} allow" for a in final_acls])
        pattern_acl = r'(#+\s*\n\s*#\s*ACL\s*\n\s*#+[\s\S]*?)(?=\n\s*#+\s*\n\s*#\s*Root)'
        if re.search(pattern_acl, content):
            new_content = re.sub(
                pattern_acl,
                rf'####################################\n    # ACL\n    ####################################\n\n{acl_lines}\n\n',
                content,
                count=1
            )
            is_ok, msg = test_unbound_syntax(new_content)
            if is_ok:
                ts = datetime.now().strftime("%Y%m%d_%H%M%S")
                shutil.copy2(UNBOUND_CONF, f"{UNBOUND_CONF}.bak_sync_{ts}")
                with open(UNBOUND_CONF, "w", encoding="utf-8") as f:
                    f.write(new_content)
                subprocess.run(["systemctl", "restart", "unbound"], capture_output=True, text=True)
                return True, "ACL Unbound tersinkronisasi"
            else:
                return False, f"Validasi sintaks Unbound gagal: {msg}"
        return False, "Blok ACL di smartdns.conf tidak ditemukan"
    except Exception as e:
        return False, str(e)

def sync_acl_to_dnsdist(final_acls):
    if not os.path.exists(DNSDIST_CONF):
        return False, f"File {DNSDIST_CONF} tidak ditemukan"
    try:
        with open(DNSDIST_CONF, "r", encoding="utf-8") as f:
            content = f.read()

        acl_lines = ',\n    '.join([f'"{a}"' for a in final_acls])
        acl_replacement = f'setACL({{\n    {acl_lines}\n}})'
        pattern_acl = r'setACL\s*\(\s*\{[^}]*\}\s*\)'
        if re.search(pattern_acl, content):
            new_content = re.sub(pattern_acl, acl_replacement, content, count=1)
            acl_comma_str = ','.join(final_acls)
            new_content = re.sub(r'(setWebserverConfig\s*\(\s*\{[\s\S]*?acl\s*=\s*)"[^"]*"', rf'\g<1>"{acl_comma_str}"', new_content, count=1)

            is_ok, msg = test_dnsdist_syntax(new_content)
            if is_ok:
                ts = datetime.now().strftime("%Y%m%d_%H%M%S")
                shutil.copy2(DNSDIST_CONF, f"{DNSDIST_CONF}.bak_sync_{ts}")
                with open(DNSDIST_CONF, "w", encoding="utf-8") as f:
                    f.write(new_content)
                subprocess.run(["systemctl", "restart", "dnsdist"], capture_output=True, text=True)
                return True, "ACL DNSDist tersinkronisasi"
            else:
                return False, f"Validasi sintaks DNSDist gagal: {msg}"
        return False, "Blok setACL di dnsdist.conf tidak ditemukan"
    except Exception as e:
        return False, str(e)

def parse_unbound_structured(content):
    data = {
        "port": 5300,
        "interfaces": [],
        "do_ip4": True,
        "do_ip6": False,
        "do_udp": True,
        "do_tcp": True,
        "acl": [],
        "domain_insecure": [],
        "hide_identity": True,
        "hide_version": True,
        "prefetch": True,
        "prefetch_key": True,
        "qname_minimisation": True,
        "cache_min_ttl": 60,
        "cache_max_ttl": 86400,
        "serve_expired": True,
        "serve_expired_ttl": 86400,
        "num_threads": 8,
        "rrset_cache_size": "512m",
        "msg_cache_size": "256m",
        "so_reuseport": True,
        "edns_buffer_size": 1232,
        "verbosity": 1,
        "log_queries": False,
        "log_replies": False
    }

    m_port = re.search(r'^\s*port:\s*(\d+)', content, re.MULTILINE)
    if m_port:
        data["port"] = int(m_port.group(1))

    interfaces = re.findall(r'^\s*interface:\s*([^\s#]+)', content, re.MULTILINE)
    data["interfaces"] = [i.strip() for i in interfaces if i.strip()]

    m = re.search(r'^\s*do-ip4:\s*(yes|no)', content, re.MULTILINE)
    if m: data["do_ip4"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*do-ip6:\s*(yes|no)', content, re.MULTILINE)
    if m: data["do_ip6"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*do-udp:\s*(yes|no)', content, re.MULTILINE)
    if m: data["do_udp"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*do-tcp:\s*(yes|no)', content, re.MULTILINE)
    if m: data["do_tcp"] = (m.group(1).lower() == "yes")

    acls = re.findall(r'^\s*access-control:\s*([^\s]+)\s+allow', content, re.MULTILINE)
    data["acl"] = [a.strip() for a in acls if a.strip()]

    insecure = re.findall(r'^\s*domain-insecure:\s*"?([^"\s#]+)"?', content, re.MULTILINE)
    data["domain_insecure"] = [d.strip() for d in insecure if d.strip()]

    m = re.search(r'^\s*hide-identity:\s*(yes|no)', content, re.MULTILINE)
    if m: data["hide_identity"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*hide-version:\s*(yes|no)', content, re.MULTILINE)
    if m: data["hide_version"] = (m.group(1).lower() == "yes")

    m = re.search(r'^\s*prefetch:\s*(yes|no)', content, re.MULTILINE)
    if m: data["prefetch"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*prefetch-key:\s*(yes|no)', content, re.MULTILINE)
    if m: data["prefetch_key"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*qname-minimisation:\s*(yes|no)', content, re.MULTILINE)
    if m: data["qname_minimisation"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*serve-expired:\s*(yes|no)', content, re.MULTILINE)
    if m: data["serve_expired"] = (m.group(1).lower() == "yes")

    m = re.search(r'^\s*cache-min-ttl:\s*(\d+)', content, re.MULTILINE)
    if m: data["cache_min_ttl"] = int(m.group(1))
    m = re.search(r'^\s*cache-max-ttl:\s*(\d+)', content, re.MULTILINE)
    if m: data["cache_max_ttl"] = int(m.group(1))
    m = re.search(r'^\s*serve-expired-ttl:\s*(\d+)', content, re.MULTILINE)
    if m: data["serve_expired_ttl"] = int(m.group(1))

    m = re.search(r'^\s*num-threads:\s*(\d+)', content, re.MULTILINE)
    if m: data["num_threads"] = int(m.group(1))
    m = re.search(r'^\s*rrset-cache-size:\s*([^\s#]+)', content, re.MULTILINE)
    if m: data["rrset_cache_size"] = m.group(1)
    m = re.search(r'^\s*msg-cache-size:\s*([^\s#]+)', content, re.MULTILINE)
    if m: data["msg_cache_size"] = m.group(1)
    m = re.search(r'^\s*so-reuseport:\s*(yes|no)', content, re.MULTILINE)
    if m: data["so_reuseport"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*edns-buffer-size:\s*(\d+)', content, re.MULTILINE)
    if m: data["edns_buffer_size"] = int(m.group(1))

    m = re.search(r'^\s*verbosity:\s*(\d+)', content, re.MULTILINE)
    if m: data["verbosity"] = int(m.group(1))
    m = re.search(r'^\s*log-queries:\s*(yes|no)', content, re.MULTILINE)
    if m: data["log_queries"] = (m.group(1).lower() == "yes")
    m = re.search(r'^\s*log-replies:\s*(yes|no)', content, re.MULTILINE)
    if m: data["log_replies"] = (m.group(1).lower() == "yes")

    return data

def update_unbound_structured(content, new_data):
    if "acl" in new_data:
        user_acls = [a.strip() for a in new_data["acl"] if a.strip()]
        final_acls = ["127.0.0.0/8", "::1/128"]
        for a in user_acls:
            if a not in final_acls:
                final_acls.append(a)
        acl_lines = "\n".join([f"    access-control: {a} allow" for a in final_acls])
        pattern_acl = r'(#+\s*\n\s*#\s*ACL\s*\n\s*#+[\s\S]*?)(?=\n\s*#+\s*\n\s*#\s*Root)'
        if re.search(pattern_acl, content):
            content = re.sub(
                pattern_acl,
                rf'####################################\n    # ACL\n    ####################################\n\n{acl_lines}\n\n',
                content,
                count=1
            )
        else:
            raise ValueError("Tidak dapat menemukan blok ACL di smartdns.conf")

    if "domain_insecure" in new_data:
        user_domains = []
        for d in new_data["domain_insecure"]:
            d_clean = d.strip().strip('"').strip("'").rstrip(".")
            if d_clean and d_clean not in user_domains:
                user_domains.append(d_clean)

        insecure_lines = "\n".join([f'    domain-insecure: "{d}"' for d in user_domains])
        if not insecure_lines:
            insecure_lines = "    # (Tidak ada domain insecure yang didaftarkan)"

        pattern_ins = r'(#+\s*\n\s*#\s*Domain Insecure\s*\n\s*#+[\s\S]*?)(?=\n\s*#+\s*\n\s*#\s*Logging|$)'
        if re.search(pattern_ins, content):
            content = re.sub(
                pattern_ins,
                rf'####################################\n    # Domain Insecure\n    ####################################\n\n{insecure_lines}\n\n',
                content,
                count=1
            )
        else:
            raise ValueError("Tidak dapat menemukan blok Domain Insecure di smartdns.conf")

    for key, field in [("do_ip4", "do-ip4"), ("do_ip6", "do-ip6"), ("do_udp", "do-udp"), ("do_tcp", "do-tcp")]:
        if key in new_data:
            val_str = "yes" if new_data[key] else "no"
            content = re.sub(rf'(^\s*{field}:\s*)(yes|no)', rf'\g<1>{val_str}', content, flags=re.MULTILINE)

    for key, field in [
        ("prefetch", "prefetch"),
        ("prefetch_key", "prefetch-key"),
        ("qname_minimisation", "qname-minimisation"),
        ("serve_expired", "serve-expired")
    ]:
        if key in new_data:
            val_str = "yes" if new_data[key] else "no"
            content = re.sub(rf'(^\s*{field}:\s*)(yes|no)', rf'\g<1>{val_str}', content, flags=re.MULTILINE)

    for key, field in [
        ("cache_min_ttl", "cache-min-ttl"),
        ("cache_max_ttl", "cache-max-ttl"),
        ("serve_expired_ttl", "serve-expired-ttl")
    ]:
        if key in new_data:
            val_int = int(new_data[key])
            content = re.sub(rf'(^\s*{field}:\s*)\d+', rf'\g<1>{val_int}', content, flags=re.MULTILINE)

    if "num_threads" in new_data:
        threads = max(1, int(new_data["num_threads"]))
        content = re.sub(r'(^\s*num-threads:\s*)\d+', rf'\g<1>{threads}', content, flags=re.MULTILINE)
        content = re.sub(r'(^\s*rrset-cache-slabs:\s*)\d+', rf'\g<1>{threads}', content, flags=re.MULTILINE)
        content = re.sub(r'(^\s*msg-cache-slabs:\s*)\d+', rf'\g<1>{threads}', content, flags=re.MULTILINE)
        content = re.sub(r'(^\s*infra-cache-slabs:\s*)\d+', rf'\g<1>{threads}', content, flags=re.MULTILINE)
        content = re.sub(r'(^\s*key-cache-slabs:\s*)\d+', rf'\g<1>{threads}', content, flags=re.MULTILINE)

    if "rrset_cache_size" in new_data and str(new_data["rrset_cache_size"]).strip():
        size_str = str(new_data["rrset_cache_size"]).strip()
        content = re.sub(r'(^\s*rrset-cache-size:\s*)[^\s#]+', rf'\g<1>{size_str}', content, flags=re.MULTILINE)

    if "msg_cache_size" in new_data and str(new_data["msg_cache_size"]).strip():
        size_str = str(new_data["msg_cache_size"]).strip()
        content = re.sub(r'(^\s*msg-cache-size:\s*)[^\s#]+', rf'\g<1>{size_str}', content, flags=re.MULTILINE)

    if "so_reuseport" in new_data:
        val_str = "yes" if new_data["so_reuseport"] else "no"
        content = re.sub(r'(^\s*so-reuseport:\s*)(yes|no)', rf'\g<1>{val_str}', content, flags=re.MULTILINE)

    if "edns_buffer_size" in new_data:
        val_int = int(new_data["edns_buffer_size"])
        content = re.sub(r'(^\s*edns-buffer-size:\s*)\d+', rf'\g<1>{val_int}', content, flags=re.MULTILINE)

    for key, field in [("hide_identity", "hide-identity"), ("hide_version", "hide-version")]:
        if key in new_data:
            val_str = "yes" if new_data[key] else "no"
            content = re.sub(rf'(^\s*{field}:\s*)(yes|no)', rf'\g<1>{val_str}', content, flags=re.MULTILINE)

    if "verbosity" in new_data or "log_queries" in new_data or "log_replies" in new_data:
        v_int = int(new_data.get("verbosity", 1))
        l_q = "yes" if new_data.get("log_queries", False) else "no"
        l_r = "yes" if new_data.get("log_replies", False) else "no"
        log_block = f"    verbosity: {v_int}\n    log-queries: {l_q}\n    log-replies: {l_r}\n"

        pattern_log = r'(#+\s*\n\s*#\s*Logging\s*\n\s*#+[\s\S]*?$)'
        if re.search(pattern_log, content):
            content = re.sub(
                pattern_log,
                rf'####################################\n    # Logging\n    ####################################\n\n{log_block}',
                content,
                count=1
            )

    return content


def get_dnsdist_console_key():
    if not os.path.exists(DNSDIST_CONF):
        return ""
    try:
        with open(DNSDIST_CONF, "r", encoding="utf-8") as f:
            content = f.read()
        m = re.search(r'setKey\("([^"]+)"\)', content)
        return m.group(1) if m else ""
    except Exception:
        return ""

def exec_dnsdist_console(command):
    key = get_dnsdist_console_key()
    if not key:
        return False, "Console key not found in dnsdist.conf"

    try:
        res = subprocess.run(
            ["dnsdist", "-k", key, "-e", command],
            capture_output=True, text=True, timeout=5
        )

        def clean_output(value):
            value = value or ""
            value = re.sub(
                r"Passing a plain-text (?:password|API key).*?instead\.",
                "",
                value,
                flags=re.IGNORECASE | re.DOTALL
            )
            return value.strip()

        stdout = clean_output(res.stdout)
        stderr = clean_output(res.stderr)

        if res.returncode == 0:
            return True, stdout

        return False, stderr or stdout or f"dnsdist exit code {res.returncode}"
    except Exception as e:
        return False, str(e)

def get_server_ips():
    import subprocess

    ipv4 = ""
    ipv6 = ""

    try:
        result = subprocess.run(
            ["ip", "-4", "route", "get", "1.1.1.1"],
            capture_output=True, text=True, timeout=2, check=False
        )
        match = re.search(r"\bsrc\s+(\d{1,3}(?:\.\d{1,3}){3})", result.stdout)
        if match:
            ipv4 = match.group(1)
    except Exception:
        pass

    try:
        result = subprocess.run(
            ["ip", "-6", "route", "get", "2606:4700:4700::1111"],
            capture_output=True, text=True, timeout=2, check=False
        )
        match = re.search(r"\bsrc\s+([0-9a-fA-F:]+)", result.stdout)
        if match:
            ipv6 = match.group(1)
    except Exception:
        pass

    return {"ipv4": ipv4, "ipv6": ipv6}


def get_tools_system_info():
    version = "Unknown"
    version_file = os.path.join(SMARTDNS_DIR, "VERSION")
    try:
        with open(version_file, "r", encoding="utf-8") as vf:
            version = vf.read().strip() or "Unknown"
    except OSError:
        pass
    uuid_val = "-"
    installed_at = "-"
    telemetry = True

    if os.path.exists(INSTALL_JSON):
        try:
            with open(INSTALL_JSON, "r", encoding="utf-8") as f:
                data = json.load(f)
                uuid_val = data.get("uuid", uuid_val)
                installed_at = data.get("installed_at", installed_at)
                telemetry = data.get("telemetry", True)
        except Exception:
            pass

    git_commit = "-"
    git_branch = "main"
    if os.path.exists(os.path.join(SMARTDNS_DIR, ".git")):
        try:
            r_c = subprocess.run(["git", "-C", SMARTDNS_DIR, "log", "-1", "--format=%h (%cr)"], capture_output=True, text=True)
            if r_c.returncode == 0:
                git_commit = r_c.stdout.strip()
            r_b = subprocess.run(["git", "-C", SMARTDNS_DIR, "branch", "--show-current"], capture_output=True, text=True)
            if r_b.returncode == 0:
                git_branch = r_b.stdout.strip()
        except Exception:
            pass

    return {
        "version": version,
        "server_ips": get_server_ips(),
        "uuid": uuid_val,
        "installed_at": installed_at,
        "telemetry": telemetry,
        "unbound_active": check_service_status("unbound"),
        "dnsdist_active": check_service_status("dnsdist"),
        "git_commit": git_commit,
        "git_branch": git_branch,
        "smartdns_home": SMARTDNS_DIR
    }

def execute_tool_command(body):
    action = body.get("action", "")

    if action == "dig":
        domain = body.get("domain", "google.com").strip()
        if not domain:
            domain = "google.com"
        if not re.match(r'^[a-zA-Z0-9.-]{1,253}$', domain) or ".." in domain or domain.startswith("-"):
            return {"success": False, "error": "Nama domain tidak valid (hanya alfanumerik, titik, dan strip).", "output": "Error: Invalid domain"}

        target = body.get("target", "ipv4")
        rtype = body.get("record_type", "A").upper()
        if rtype not in ["A", "AAAA", "CNAME", "MX", "TXT", "NS", "PTR", "SOA", "ANY"]:
            rtype = "A"
        short = bool(body.get("short", False))

        if target == "all":
            targets = [
                ("@127.0.0.1", "Frontend IPv4 (Port 53)", ["dig"] + (["+short"] if short else []) + ["@127.0.0.1", domain, rtype]),
                ("@::1", "Frontend IPv6 (Port 53)", ["dig"] + (["+short"] if short else []) + ["@::1", domain, rtype]),
                ("@127.0.0.1 -p 5300", "Recursive Unbound (Port 5300)", ["dig"] + (["+short"] if short else []) + ["@127.0.0.1", "-p", "5300", domain, rtype])
            ]
            combined = []
            overall_success = True
            for s_addr, s_label, cmd in targets:
                try:
                    res = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
                    out = (res.stdout + ("\n" + res.stderr if res.stderr else "")).strip()
                    status_str = "OK (Code 0)" if res.returncode == 0 else f"GAGAL (Code {res.returncode})"
                    combined.append(f"=== [{s_label}] {' '.join(cmd)} [{status_str}] ===\n{out}\n")
                    if res.returncode != 0:
                        overall_success = False
                except Exception as ex:
                    combined.append(f"=== [{s_label}] {' '.join(cmd)} [ERROR] ===\n{ex}\n")
                    overall_success = False
            return {
                "success": overall_success,
                "command": f"dig @127.0.0.1 & dig @::1 & dig @127.0.0.1 -p 5300 {domain} {rtype}",
                "description": f"Uji Semua Resolusi DNS untuk '{domain}' ({rtype})",
                "output": "\n".join(combined),
                "exit_code": 0 if overall_success else 1
            }

        cmd = ["dig"]
        if short:
            cmd.append("+short")

        if target == "ipv4":
            cmd.extend(["@127.0.0.1", domain, rtype])
            desc = f"dig @127.0.0.1 {domain} {rtype}"
        elif target == "ipv6":
            cmd.extend(["@::1", domain, rtype])
            desc = f"dig @::1 {domain} {rtype}"
        elif target == "recursive":
            cmd.extend(["@127.0.0.1", "-p", "5300", domain, rtype])
            desc = f"dig @127.0.0.1 -p 5300 {domain} {rtype}"
        else:
            return {"success": False, "error": f"Target dig '{target}' tidak dikenal."}

        try:
            t0 = time.time()
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=12)
            elapsed_ms = round((time.time() - t0) * 1000, 2)
            raw_out = (res.stdout + ("\n" + res.stderr if res.stderr else "")).strip()
            return {
                "success": (res.returncode == 0),
                "command": " ".join(cmd),
                "description": desc,
                "output": raw_out if raw_out else "[Tidak ada output dari server]",
                "exit_code": res.returncode,
                "elapsed_ms": elapsed_ms
            }
        except subprocess.TimeoutExpired:
            return {"success": False, "command": " ".join(cmd), "error": "Perintah dig timeout (lebih dari 12 detik).", "output": "Timeout: No response from DNS server"}
        except Exception as e:
            return {"success": False, "command": " ".join(cmd), "error": str(e), "output": str(e)}

    elif action == "checkconf":
        component = body.get("component", "unbound")
        if component == "unbound":
            cmd = ["unbound-checkconf"]
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                out = (res.stdout + "\n" + res.stderr).strip()
                return {
                    "success": (res.returncode == 0),
                    "command": "unbound-checkconf",
                    "description": "Pengecekan sintaks konfigurasi Unbound (/etc/unbound/unbound.conf)",
                    "output": out if out else "unbound-checkconf: no errors",
                    "exit_code": res.returncode
                }
            except Exception as e:
                return {"success": False, "command": "unbound-checkconf", "output": str(e), "error": str(e)}

        elif component == "dnsdist":
            cmd = ["dnsdist", "--check-config"]
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                out = (res.stdout + "\n" + res.stderr).strip()
                warnings = (
                    "Passing a plain-text password via the 'password' parameter",
                    "Passing a plain-text API key via the 'apiKey' parameter",
                )
                out = "\n".join(
                    line for line in out.splitlines()
                    if not any(warning in line for warning in warnings)
                ).strip()
                return {
                    "success": (res.returncode == 0),
                    "command": "dnsdist --check-config",
                    "description": "Pengecekan sintaks konfigurasi dnsdist (/etc/dnsdist/dnsdist.conf)",
                    "output": out if out else "Configuration '/etc/dnsdist/dnsdist.conf' OK!",
                    "exit_code": res.returncode
                }
            except Exception as e:
                return {"success": False, "command": "dnsdist --check-config", "output": str(e), "error": str(e)}

        elif component == "both":
            r1 = subprocess.run(["unbound-checkconf"], capture_output=True, text=True, timeout=10)
            r2 = subprocess.run(["dnsdist", "--check-config"], capture_output=True, text=True, timeout=10)
            out = f"--- [1/2] UNBOUND CHECKCONF ---\n{(r1.stdout + chr(10) + r1.stderr).strip() or 'OK'}\n\n--- [2/2] DNSDIST CHECK-CONFIG ---\n{(r2.stdout + chr(10) + r2.stderr).strip() or 'OK'}"
            return {
                "success": (r1.returncode == 0 and r2.returncode == 0),
                "command": "unbound-checkconf && dnsdist --check-config",
                "description": "Pengecekan sintaks lengkap Unbound dan dnsdist",
                "output": out,
                "exit_code": max(r1.returncode, r2.returncode)
            }
        else:
            return {"success": False, "error": f"Komponen checkconf '{component}' tidak valid"}

    elif action == "service_status":
        service = body.get("service", "unbound")
        if service not in ["unbound", "dnsdist"]:
            return {"success": False, "error": f"Service '{service}' tidak diizinkan."}
        try:
            res = subprocess.run(["systemctl", "status", service, "--no-pager", "-n", "30"], capture_output=True, text=True, timeout=10)
            out = (res.stdout + "\n" + res.stderr).strip()
            return {
                "success": (res.returncode == 0 or "active (running)" in out),
                "command": f"systemctl status {service}",
                "description": f"Status service {service}",
                "output": out,
                "exit_code": res.returncode
            }
        except Exception as e:
            return {"success": False, "command": f"systemctl status {service}", "output": str(e), "error": str(e)}

    elif action == "service_restart":
        service = body.get("service", "unbound")
        if service not in ["unbound", "dnsdist", "both"]:
            return {"success": False, "error": f"Service '{service}' tidak diizinkan."}
        try:
            if service == "both":
                cmd_str = "systemctl restart unbound && systemctl restart dnsdist"
                r1 = subprocess.run(["systemctl", "restart", "unbound"], capture_output=True, text=True, timeout=15)
                r2 = subprocess.run(["systemctl", "restart", "dnsdist"], capture_output=True, text=True, timeout=15)
                s1 = subprocess.run(["systemctl", "status", "unbound", "--no-pager", "-n", "5"], capture_output=True, text=True, timeout=5)
                s2 = subprocess.run(["systemctl", "status", "dnsdist", "--no-pager", "-n", "5"], capture_output=True, text=True, timeout=5)
                out = f"Restart Unbound: {'SUKSES' if r1.returncode==0 else 'GAGAL ('+r1.stderr+')'}\n{s1.stdout}\n\nRestart DNSDist: {'SUKSES' if r2.returncode==0 else 'GAGAL ('+r2.stderr+')'}\n{s2.stdout}"
                return {
                    "success": (r1.returncode == 0 and r2.returncode == 0),
                    "command": cmd_str,
                    "description": "Restart service Unbound & DNSDist",
                    "output": out,
                    "exit_code": max(r1.returncode, r2.returncode)
                }
            else:
                cmd_str = f"systemctl restart {service}"
                r = subprocess.run(["systemctl", "restart", service], capture_output=True, text=True, timeout=15)
                s = subprocess.run(["systemctl", "status", service, "--no-pager", "-n", "10"], capture_output=True, text=True, timeout=5)
                out = f"Restart {service}: {'SUKSES' if r.returncode==0 else 'GAGAL'}\n\n{s.stdout}"
                return {
                    "success": (r.returncode == 0),
                    "command": cmd_str,
                    "description": f"Restart service {service}",
                    "output": out,
                    "exit_code": r.returncode
                }
        except Exception as e:
            return {"success": False, "command": f"systemctl restart {service}", "output": str(e), "error": str(e)}

    elif action == "heartbeat":
        try:
            heartbeat_cmd = "sed '/sleep/d' /usr/local/bin/smartdns-heartbeat | bash"
            res = subprocess.run(["bash", "-c", heartbeat_cmd], capture_output=True, text=True, timeout=25)
            out = (res.stdout + "\n" + res.stderr).strip()

            meta = ""
            if os.path.exists(INSTALL_JSON):
                with open(INSTALL_JSON, "r", encoding="utf-8") as f:
                    meta = f.read().strip()

            full_out = "Kirim Heartbeat Telemetry ke https://smartdns.mynoc.id/api/v1/heartbeat.php\n"
            full_out += f"Status: {'BERHASIL (Exit Code 0)' if res.returncode == 0 else 'GAGAL (Exit Code ' + str(res.returncode) + ')'}\n"
            if out:
                full_out += f"\nDetail Eksekusi:\n{out}\n"
            if meta:
                full_out += f"\nMetadata Terkirim (/var/lib/smartdns/install.json):\n{meta}"

            return {
                "success": (res.returncode == 0),
                "command": "/usr/local/bin/smartdns-heartbeat",
                "description": "Manual Heartbeat & Telemetry Registration",
                "output": full_out,
                "exit_code": res.returncode
            }
        except Exception as e:
            return {"success": False, "command": "/usr/local/bin/smartdns-heartbeat", "output": str(e), "error": str(e)}

    elif action == "metadata":
        try:
            if not os.path.exists(INSTALL_JSON):
                return {"success": False, "command": f"cat {INSTALL_JSON}", "output": f"File {INSTALL_JSON} tidak ditemukan."}
            with open(INSTALL_JSON, "r", encoding="utf-8") as f:
                content = f.read()
            return {
                "success": True,
                "command": f"cat {INSTALL_JSON}",
                "description": "Installation Metadata (UUID & Version)",
                "output": content,
                "exit_code": 0
            }
        except Exception as e:
            return {"success": False, "command": f"cat {INSTALL_JSON}", "output": str(e), "error": str(e)}

    elif action == "install_env":
        try:
            if not os.path.exists(INSTALL_ENV):
                return {"success": False, "command": f"cat {INSTALL_ENV}", "output": f"File {INSTALL_ENV} tidak ditemukan."}
            with open(INSTALL_ENV, "r", encoding="utf-8") as f:
                content = f.read()
            return {
                "success": True,
                "command": f"cat {INSTALL_ENV}",
                "description": "Installation Path & Environment (/var/lib/smartdns/install.env)",
                "output": content,
                "exit_code": 0
            }
        except Exception as e:
            return {"success": False, "command": f"cat {INSTALL_ENV}", "output": str(e), "error": str(e)}

    else:
        return {"success": False, "error": f"Action '{action}' tidak dikenal"}

def trigger_system_update(update_type):
    global active_tool_update
    if active_tool_update["running"]:
        return {"error": "Proses update sedang berjalan. Mohon tunggu hingga selesai."}, 409

    if not os.path.isdir(SMARTDNS_DIR):
        return {"error": f"Direktori {SMARTDNS_DIR} tidak ditemukan."}, 404

    valid_types = ["patch"]
    if update_type not in valid_types:
        return {"error": f"Tipe update '{update_type}' tidak valid."}, 400

    import threading
    def run_update_thread():
        global active_tool_update
        active_tool_update["running"] = True
        active_tool_update["status"] = "running"
        active_tool_update["type"] = update_type
        active_tool_update["start_time"] = time.time()

        os.makedirs(os.path.dirname(MAINTENANCE_LOG), exist_ok=True)
        with open(MAINTENANCE_LOG, "w", encoding="utf-8") as log_f:
            start_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_f.write("===========================================================\n")
            log_f.write("  SmartDNS System Maintenance / Update Tool\n")
            log_f.write(f"  Waktu Mulai: {start_ts}\n")
            log_f.write(f"  Tipe Update: {update_type.upper()}\n")
            log_f.write("===========================================================\n\n")
            log_f.flush()

            cmd_bash = ""
            if update_type == "patch":
                log_f.write(f">>> Menjalankan: cd {SMARTDNS_DIR} && bash update.sh --patch\n\n")
                log_f.flush()
                cmd_bash = f"cd {SMARTDNS_DIR} && bash update.sh --patch"
            elif update_type == "force":
                try:
                    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
                    if os.path.exists(DNSDIST_CONF):
                        shutil.copy2(DNSDIST_CONF, f"{DNSDIST_CONF}.bak_forceupdate_{ts}")
                        log_f.write(f">>> [BACKUP] /etc/dnsdist/dnsdist.conf berhasil dibackup ke .bak_forceupdate_{ts}\n")
                except Exception as b_err:
                    log_f.write(f">>> [WARN] Gagal backup dnsdist.conf: {b_err}\n")
                log_f.write(f">>> Menjalankan: cd {SMARTDNS_DIR} && git fetch origin && git reset --hard origin/main && yes \"\" | bash install.sh\n\n")
                log_f.flush()
                cmd_bash = f"cd {SMARTDNS_DIR} && git fetch origin && git reset --hard origin/main && yes \"\" | bash install.sh"
            elif update_type == "standard":
                try:
                    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
                    if os.path.exists(DNSDIST_CONF):
                        shutil.copy2(DNSDIST_CONF, f"{DNSDIST_CONF}.bak_standardupdate_{ts}")
                except Exception:
                    pass
                log_f.write(f">>> Menjalankan: cd {SMARTDNS_DIR} && git pull && yes \"\" | bash install.sh\n\n")
                log_f.flush()
                cmd_bash = f"cd {SMARTDNS_DIR} && git pull && yes \"\" | bash install.sh"

            try:
                proc = subprocess.Popen(
                    cmd_bash,
                    shell=True,
                    stdout=log_f,
                    stderr=subprocess.STDOUT,
                    cwd=SMARTDNS_DIR
                )
                active_tool_update["pid"] = proc.pid
                ret = proc.wait()
                end_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                log_f.write(f"\n===========================================================\n")
                log_f.write(f"  Proses selesai pada: {end_ts} (Exit Code: {ret})\n")
                log_f.write(f"===========================================================\n")
                active_tool_update["status"] = "finished" if ret == 0 else "failed"
            except Exception as ex:
                log_f.write(f"\n[EXCEPTION] Gagal menjalankan update: {ex}\n")
                active_tool_update["status"] = "failed"
            finally:
                active_tool_update["running"] = False

    t = threading.Thread(target=run_update_thread, daemon=True)
    t.start()
    return {"success": True, "message": f"Proses pembaruan '{update_type}' telah dimulai di latar belakang."}, 200

def parse_dnsdist_structured(content):
    data = {
        "spoof_ipv4": [],
        "spoof_ipv6": [],
        "whitelist": [],
        "acl": [],
        "webserver_password": "",
        "webserver_port": "8083",
        "rate_limit": {"enabled": False, "qps": 100, "action": "DropAction"},
        "server_policy": "leastOutstanding",
        "upstream_servers": [],
        "custom_dns": [],
        "safesearch": {"google": False, "bing": False, "youtube": False, "duckduckgo": False},
        "query_logging": False
    }

    # 1. Parse Block AAAA (IPv6 Spoof)
    m_v6 = re.search(
        r'-- Block AAAA[\s\S]*?SpoofAction\s*\(\s*\{([^}]+)\}\s*\)',
        content
    )
    if m_v6:
        raw_ips = re.findall(r'"([^"]+)"', m_v6.group(1))
        data["spoof_ipv6"] = [ip.strip() for ip in raw_ips if ip.strip()]

    # 2. Parse Block A (IPv4 Spoof)
    m_v4 = re.search(
        r'-- Block A\b[\s\S]*?SpoofAction\s*\(\s*\{([^}]+)\}\s*\)',
        content
    )
    if m_v4:
        raw_ips = re.findall(r'"([^"]+)"', m_v4.group(1))
        data["spoof_ipv4"] = [ip.strip() for ip in raw_ips if ip.strip()]

    # 3. Parse Whitelist domains
    wl_domains = re.findall(r'whitelistSMN:add\s*\(\s*newDNSName\s*\(\s*"([^"]+)"\s*\)\s*\)', content)
    data["whitelist"] = [d.strip() for d in wl_domains if d.strip()]

    # 4. Parse ACL
    m_acl = re.search(r'setACL\s*\(\s*\{([^}]+)\}\s*\)', content)
    if m_acl:
        raw_acls = re.findall(r'"([^"]+)"', m_acl.group(1))
        data["acl"] = [a.strip() for a in raw_acls if a.strip()]

    # 5. Parse Webserver password & port
    m_port = re.search(r'webserver\s*\(\s*"[^"]*:(\d+)"\s*\)', content)
    if m_port:
        data["webserver_port"] = m_port.group(1)

    m_pw = re.search(r'setWebserverConfig\s*\(\s*\{[\s\S]*?password\s*=\s*"([^"]*)"', content)
    if m_pw:
        data["webserver_password"] = m_pw.group(1)

    # 6. Parse Rate Limit
    m_rl = re.search(r'addAction\s*\(\s*MaxQPSIPRule\s*\(\s*(\d+)\s*\)\s*,\s*(\w+)\s*\([^)]*\)\s*\)', content)
    if m_rl:
        data["rate_limit"] = {
            "enabled": True,
            "qps": int(m_rl.group(1)),
            "action": m_rl.group(2)
        }

    # 7. Parse Server Policy & Upstreams
    m_pol = re.search(r'setServerPolicy\s*\(\s*(\w+)\s*\)', content)
    if m_pol:
        data["server_policy"] = m_pol.group(1)

    sb_list = re.findall(r'newServer\s*\(\s*\{([^}]+)\}\s*\)', content)
    for sb in sb_list:
        m_addr = re.search(r'address\s*=\s*"([^"]+)"', sb)
        m_name = re.search(r'name\s*=\s*"([^"]+)"', sb)
        m_chk = re.search(r'checkName\s*=\s*"([^"]+)"', sb)
        m_to = re.search(r'timeout\s*=\s*(\d+)', sb)
        if m_addr:
            data["upstream_servers"].append({
                "name": m_name.group(1) if m_name else "",
                "address": m_addr.group(1),
                "checkName": m_chk.group(1) if m_chk else "",
                "timeout": int(m_to.group(1)) if m_to else 2
            })

    # 8. Parse Custom DNS Override
    m_cb = re.search(r'-- Custom DNS Override([\s\S]*?)(?:-- SafeSearch|-- Block AAAA|-- Rate Limit)', content)
    if m_cb:
        records = re.findall(r'addAction\s*\(\s*"([^"]+)"\s*,\s*SpoofAction\s*\(\s*\{?"([^"}]+)"\}?\s*\)\s*\)', m_cb.group(1))
        for dom, ip in records:
            data["custom_dns"].append({"domain": dom, "ip": ip})

    # 9. Parse SafeSearch
    data["safesearch"] = {
        "google": bool(re.search(r'googleSafeSMN', content)),
        "bing": bool(re.search(r'bingSafeSMN', content)),
        "youtube": bool(re.search(r'ytSafeSMN', content)),
        "duckduckgo": bool(re.search(r'ddgSafeSMN', content))
    }

    # 10. Query Logging
    data["query_logging"] = bool(re.search(r'LogAction\s*\(\s*"/var/log/dnsdist_queries\.log"', content))

    return data

def update_dnsdist_structured(content, new_data):
    # 1. Update IPv6 SpoofAction
    if "spoof_ipv6" in new_data:
        ips_v6 = [ip.strip() for ip in new_data["spoof_ipv6"] if ip.strip()]
        if not ips_v6:
            raise ValueError("IPv6 Spoof IP tidak boleh kosong")
        formatted_v6 = '{"' + '","'.join(ips_v6) + '"}'
        pattern_v6 = r'(-- Block AAAA[\s\S]*?SpoofAction\s*\(\s*)\{[^}]+\}(\s*\))'
        if re.search(pattern_v6, content):
            content = re.sub(pattern_v6, rf'\g<1>{formatted_v6}\g<2>', content, count=1)
        else:
            raise ValueError("Tidak dapat menemukan blok aturan Block AAAA (SpoofAction IPv6) di config")

    # 2. Update IPv4 SpoofAction
    if "spoof_ipv4" in new_data:
        ips_v4 = [ip.strip() for ip in new_data["spoof_ipv4"] if ip.strip()]
        if not ips_v4:
            raise ValueError("IPv4 Spoof IP tidak boleh kosong")
        formatted_v4 = '{"' + '","'.join(ips_v4) + '"}'
        pattern_v4 = r'(-- Block A\b[\s\S]*?SpoofAction\s*\(\s*)\{[^}]+\}(\s*\))'
        if re.search(pattern_v4, content):
            content = re.sub(pattern_v4, rf'\g<1>{formatted_v4}\g<2>', content, count=1)
        else:
            raise ValueError("Tidak dapat menemukan blok aturan Block A (SpoofAction IPv4) di config")

    # 3. Update Whitelist
    if "whitelist" in new_data:
        wl_list = []
        for d in new_data["whitelist"]:
            d = d.strip()
            if not d:
                continue
            if not d.endswith("."):
                d += "."
            wl_list.append(d)
        
        wl_lines = [f'whitelistSMN:add(newDNSName("{d}"))' for d in wl_list]
        wl_block_replacement = "\n".join(wl_lines) if wl_lines else "-- (No whitelist entries)"

        pattern_wl = r'(local\s+whitelistSMN\s*=\s*newSuffixMatchNode\(\s*\))[\s\S]*?(addAction\s*\(\s*SuffixMatchNodeRule\s*\(\s*whitelistSMN\s*\))'
        if re.search(pattern_wl, content):
            content = re.sub(pattern_wl, rf'\g<1>\n\n{wl_block_replacement}\n\n\g<2>', content, count=1)
        else:
            raise ValueError("Tidak dapat menemukan blok Whitelist (whitelistSMN) di config")

    # 4. Update ACL (Baris 1 dan 2: 127.0.0.0/8 dan ::1/128 default tidak bisa dihapus)
    if "acl" in new_data:
        user_acls = [a.strip() for a in new_data["acl"] if a.strip()]
        final_acls = ["127.0.0.0/8", "::1/128"]
        for a in user_acls:
            if a not in final_acls:
                final_acls.append(a)

        acl_lines = ',\n    '.join([f'"{a}"' for a in final_acls])
        acl_replacement = f'setACL({{\n    {acl_lines}\n}})'

        pattern_acl = r'setACL\s*\(\s*\{[^}]*\}\s*\)'
        if re.search(pattern_acl, content):
            content = re.sub(pattern_acl, acl_replacement, content, count=1)
        else:
            raise ValueError("Tidak dapat menemukan blok setACL di config")

        # Sinkronkan parameter acl di setWebserverConfig jika ada
        acl_comma_str = ','.join(final_acls)
        content = re.sub(r'(setWebserverConfig\s*\(\s*\{[\s\S]*?acl\s*=\s*)"[^"]*"', rf'\g<1>"{acl_comma_str}"', content, count=1)

    # 5. Update Webserver Password
    if "webserver_password" in new_data:
        new_pw = new_data["webserver_password"].strip()
        if not new_pw:
            raise ValueError("Password PowerDNS Web Panel tidak boleh kosong")
        pattern_pw = r'(setWebserverConfig\s*\(\s*\{[\s\S]*?password\s*=\s*)"[^"]*"'
        if re.search(pattern_pw, content):
            content = re.sub(pattern_pw, rf'\g<1>"{new_pw}"', content, count=1)
        else:
            raise ValueError("Tidak dapat menemukan setWebserverConfig password di config")

    # 6. Update Rate Limit
    if "rate_limit" in new_data:
        rl = new_data["rate_limit"]
        if rl.get("enabled"):
            qps = int(rl.get("qps", 100))
            action = rl.get("action", "DropAction")
            if action not in ["DropAction", "DelayAction", "TruncateAction"]:
                action = "DropAction"
            action_call = "DelayAction(50)" if action == "DelayAction" else f"{action}()"
            rl_code = f"addAction(MaxQPSIPRule({qps}), {action_call})"
        else:
            rl_code = ""

        pattern_rl = r'(-- Rate Limit\s*[-]*\s*\n)[\s\S]*?(\n\s*----------------------------------------------------\n-- Forward Normal DNS)'
        if re.search(pattern_rl, content):
            content = re.sub(pattern_rl, rf'\g<1>\n{rl_code}\n\g<2>', content, count=1)

    # 7. Update Upstream Servers & Policy
    if "upstream_servers" in new_data or "server_policy" in new_data:
        policy = new_data.get("server_policy", "leastOutstanding")
        servers = new_data.get("upstream_servers", [])
        if servers:
            srv_lines = []
            for s in servers:
                addr = s.get("address", "").strip()
                if not addr:
                    continue
                name = s.get("name", "").strip() or addr.replace(".", "_").replace(":", "_")
                chk = s.get("checkName", "").strip()
                to = s.get("timeout", 2)
                props = [f'address="{addr}"', f'name="{name}"']
                if chk:
                    if not chk.endswith("."):
                        chk += "."
                    props.extend([f'checkName="{chk}"', 'mustResolve=true', f'timeout={to}', 'checkInterval=10'])
                srv_lines.append('newServer({\n    ' + ',\n    '.join(props) + '\n})')

            srv_block = '\n\n'.join(srv_lines) + f'\n\nsetServerPolicy({policy})'
            pattern_backend = r'(-- Backend\s*[-]*\s*\n)[\s\S]*?(\n\s*-- Packet Cache)'
            if re.search(pattern_backend, content):
                content = re.sub(pattern_backend, rf'\g<1>\n{srv_block}\n\g<2>', content, count=1)

    # 8. Update Custom DNS Override
    if "custom_dns" in new_data:
        custom_records = new_data["custom_dns"]
        rec_lines = []
        for item in custom_records:
            d = item.get("domain", "").strip()
            ip = item.get("ip", "").strip()
            if d and ip:
                if not d.endswith("."):
                    d += "."
                rec_lines.append(f'addAction("{d}", SpoofAction({{"{ip}"}}))')
        custom_block_content = "\n".join(rec_lines)
        header_custom = "----------------------------------------------------\n-- Custom DNS Override\n----------------------------------------------------"

        if "-- Custom DNS Override" in content:
            pattern_c = r'(-- Custom DNS Override\s*[-]*\s*\n)[\s\S]*?(\n\s*----------------------------------------------------\n--(?: SafeSearch| Block AAAA))'
            content = re.sub(pattern_c, rf'\g<1>\n{custom_block_content}\n\g<2>', content, count=1)
        elif custom_block_content:
            pattern_before = r'(\n----------------------------------------------------\n-- Block AAAA)'
            content = re.sub(pattern_before, f'\n{header_custom}\n\n{custom_block_content}\n\\1', content, count=1)

    # 9. Update SafeSearch Enforcement
    if "safesearch" in new_data:
        ss = new_data["safesearch"]
        ss_blocks = []
        if ss.get("google"):
            ss_blocks.append('''local googleSafeSMN = newSuffixMatchNode()
googleSafeSMN:add(newDNSName("google.com."))
googleSafeSMN:add(newDNSName("google.co.id."))
googleSafeSMN:add(newDNSName("www.google.com."))
googleSafeSMN:add(newDNSName("www.google.co.id."))
addAction(AndRule({SuffixMatchNodeRule(googleSafeSMN), QTypeRule(DNSQType.A)}), SpoofAction("216.239.38.120"))
addAction(AndRule({SuffixMatchNodeRule(googleSafeSMN), QTypeRule(DNSQType.AAAA)}), SpoofAction("2001:4860:4806::78"))''')
        if ss.get("bing"):
            ss_blocks.append('''local bingSafeSMN = newSuffixMatchNode()
bingSafeSMN:add(newDNSName("bing.com."))
bingSafeSMN:add(newDNSName("www.bing.com."))
addAction(AndRule({SuffixMatchNodeRule(bingSafeSMN), QTypeRule(DNSQType.A)}), SpoofAction("204.79.197.220"))''')
        if ss.get("youtube"):
            ss_blocks.append('''local ytSafeSMN = newSuffixMatchNode()
ytSafeSMN:add(newDNSName("youtube.com."))
ytSafeSMN:add(newDNSName("www.youtube.com."))
ytSafeSMN:add(newDNSName("m.youtube.com."))
ytSafeSMN:add(newDNSName("youtubei.googleapis.com."))
addAction(AndRule({SuffixMatchNodeRule(ytSafeSMN), QTypeRule(DNSQType.A)}), SpoofAction("216.239.38.120"))''')
        if ss.get("duckduckgo"):
            ss_blocks.append('''local ddgSafeSMN = newSuffixMatchNode()
ddgSafeSMN:add(newDNSName("duckduckgo.com."))
addAction(AndRule({SuffixMatchNodeRule(ddgSafeSMN), QTypeRule(DNSQType.A)}), SpoofAction("52.142.124.215"))''')

        ss_content = "\n\n".join(ss_blocks)
        header_ss = "----------------------------------------------------\n-- SafeSearch Enforcement\n----------------------------------------------------"

        if "-- SafeSearch Enforcement" in content:
            pattern_ss = r'(-- SafeSearch Enforcement\s*[-]*\s*\n)[\s\S]*?(\n\s*----------------------------------------------------\n-- Block AAAA)'
            content = re.sub(pattern_ss, rf'\g<1>\n{ss_content}\n\g<2>', content, count=1)
        elif ss_content:
            pattern_before = r'(\n----------------------------------------------------\n-- Block AAAA)'
            content = re.sub(pattern_before, f'\n{header_ss}\n\n{ss_content}\n\\1', content, count=1)

    # 10. Update Query Log
    if "query_logging" in new_data:
        ql = new_data["query_logging"]
        ql_code = 'addAction(AllRule(), LogAction("/var/log/dnsdist_queries.log", false, false, false))' if ql else ''
        pattern_ql = r'(-- Query Log\s*[-]*\s*\n)[\s\S]*$'
        content = re.sub(pattern_ql, rf'\g<1>\n{ql_code}\n', content, count=1)

    return content


def get_live_analytics():
    analytics = {
        "connected": False,
        "stats": {},
        "servers": [],
        "top_queries": [],
        "top_responses": []
    }
    # 1. dumpStats
    ok, out = exec_dnsdist_console("dumpStats()")
    if ok:
        analytics["connected"] = True
        stats_map = {}
        for line in out.splitlines():
            tokens = line.split()
            for i in range(0, len(tokens)-1, 2):
                k = tokens[i]
                v = tokens[i+1]
                try:
                    stats_map[k] = float(v) if '.' in v else int(v)
                except Exception:
                    stats_map[k] = v
        analytics["stats"] = stats_map

    # 2. showServers
    ok_srv, out_srv = exec_dnsdist_console("showServers()")
    if ok_srv:
        servers = []
        for line in out_srv.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("All"):
                continue
            parts = line.split()
            if len(parts) >= 10:
                try:
                    servers.append({
                        "id": parts[0],
                        "name": parts[1],
                        "address": parts[2],
                        "state": parts[3],
                        "qps": float(parts[4]),
                        "queries": int(parts[8]),
                        "drops": int(parts[9]),
                        "latency": float(parts[11]) if len(parts) > 11 else 0.0
                    })
                except Exception:
                    pass
        analytics["servers"] = servers

    # 3. topQueries(15)
    ok_q, out_q = exec_dnsdist_console("topQueries(15)")
    if ok_q:
        queries = []
        for line in out_q.splitlines():
            parts = line.split()
            if len(parts) >= 3:
                domain = parts[1]
                count = parts[2]
                pct = parts[3] if len(parts) >= 4 else ""
                queries.append({"domain": domain, "count": count, "pct": pct})
        analytics["top_queries"] = queries

    # 4. topResponses(15)
    ok_r, out_r = exec_dnsdist_console("topResponses(15)")
    if ok_r:
        responses = []
        for line in out_r.splitlines():
            parts = line.split()
            if len(parts) >= 3:
                domain = parts[1]
                count = parts[2]
                pct = parts[3] if len(parts) >= 4 else ""
                responses.append({"domain": domain, "count": count, "pct": pct})
        analytics["top_responses"] = responses

    return analytics



# Lightweight host metrics for the Overview dashboard.
_metrics_prev = {}

def get_system_metrics():
    global _metrics_prev
    now = time.monotonic()
    result = {"cpu_percent": 0, "ram_used_mb": 0, "ram_total_mb": 0,
              "ram_percent": 0, "swap_used_mb": 0, "disk_used_gb": 0,
              "disk_total_gb": 0, "disk_percent": 0, "disk_read_mbs": 0,
              "disk_write_mbs": 0, "disk_io_wait": 0, "rx_mbps": 0,
              "tx_mbps": 0, "rx_pps": 0, "tx_pps": 0, "interfaces": []}
    try:
        with open("/proc/stat", "r", encoding="utf-8") as f:
            vals = list(map(int, f.readline().split()[1:]))
        idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
        total = sum(vals)
        old = _metrics_prev.get("cpu")
        if old:
            dt, di = total - old[0], idle - old[1]
            result["cpu_percent"] = round(max(0, min(100, 100 * (dt-di) / dt)), 1) if dt else 0
        _metrics_prev["cpu"] = (total, idle)
    except Exception:
        pass
    try:
        mem = {}
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                k, v = line.split(":", 1)
                mem[k] = int(v.strip().split()[0]) * 1024
        total = mem.get("MemTotal", 0)
        avail = mem.get("MemAvailable", mem.get("MemFree", 0))
        used = max(0, total-avail)
        result.update(ram_used_mb=round(used/1048576, 1),
                      ram_total_mb=round(total/1048576, 1),
                      ram_percent=round(100*used/total, 1) if total else 0)
        st, sf = mem.get("SwapTotal", 0), mem.get("SwapFree", 0)
        result["swap_used_mb"] = round(max(0, st-sf)/1048576, 1)
    except Exception:
        pass
    try:
        du = shutil.disk_usage("/")
        result.update(disk_used_gb=round((du.total-du.free)/1e9, 1),
                      disk_total_gb=round(du.total/1e9, 1),
                      disk_percent=round(100*(du.total-du.free)/du.total, 1) if du.total else 0)
    except Exception:
        pass
    # Aggregate physical network interfaces; exclude loopback and virtual lo.
    rx_b = tx_b = rx_p = tx_p = 0
    try:
        with open("/proc/net/dev", "r", encoding="utf-8") as f:
            for line in f.readlines()[2:]:
                if ":" not in line: continue
                name, data = line.split(":", 1)
                name = name.strip()
                if name == "lo": continue
                # Prefer physical/device-backed NICs to avoid double-counting bridges.
                if not os.path.exists(os.path.join("/sys/class/net", name, "device")):
                    continue
                v = list(map(int, data.split()))
                if len(v) >= 16:
                    rx_b += v[0]; rx_p += v[1]; tx_b += v[8]; tx_p += v[9]
                    result["interfaces"].append(name)
        prev = _metrics_prev.get("net")
        if prev:
            elapsed = max(now-prev[0], 0.001)
            result["rx_mbps"] = round(max(0, rx_b-prev[1])*8/elapsed/1e6, 2)
            result["tx_mbps"] = round(max(0, tx_b-prev[2])*8/elapsed/1e6, 2)
            result["rx_pps"] = round(max(0, rx_p-prev[3])/elapsed)
            result["tx_pps"] = round(max(0, tx_p-prev[4])/elapsed)
        _metrics_prev["net"] = (now, rx_b, tx_b, rx_p, tx_p)
    except Exception:
        pass
    # Disk counters in /proc/diskstats: sectors are 512 bytes; aggregate devices.
    try:
        read_sectors = write_sectors = io_ms = 0
        with open("/proc/diskstats", "r", encoding="utf-8") as f:
            for line in f:
                a = line.split()
                if len(a) >= 14:
                    name = a[2]
                    if name.startswith(("loop", "ram", "zram", "dm-")): continue
                    read_sectors += int(a[5]); write_sectors += int(a[9]); io_ms += int(a[12])
        prev = _metrics_prev.get("disk")
        if prev:
            elapsed = max(now-prev[0], 0.001)
            result["disk_read_mbs"] = round(max(0, read_sectors-prev[1])*512/elapsed/1e6, 2)
            result["disk_write_mbs"] = round(max(0, write_sectors-prev[2])*512/elapsed/1e6, 2)
            result["disk_io_wait"] = round(max(0, io_ms-prev[3])/(elapsed*10), 1)
        _metrics_prev["disk"] = (now, read_sectors, write_sectors, io_ms)
    except Exception:
        pass
    result["interfaces"] = sorted(set(result["interfaces"]))
    return result


class SmartDNSHandler(BaseHTTPRequestHandler):
    server_version = "SmartDNS-UI/1.0"

    def _send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.end_headers()
        self.wfile.write(body)

    def _get_cookie(self, name):
        cookie_header = self.headers.get("Cookie", "")
        for pair in cookie_header.split(";"):
            pair = pair.strip()
            if "=" in pair:
                k, v = pair.split("=", 1)
                if k.strip() == name:
                    return v.strip()
        return None

    def _is_authenticated(self):
        token = self._get_cookie("smartdns_session")
        if not token:
            auth_header = self.headers.get("Authorization", "")
            if auth_header.startswith("Bearer "):
                token = auth_header[7:].strip()
        return token in active_sessions if token else False

    def _read_json_body(self):
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length <= 0:
            return {}
        raw = self.rfile.read(content_length).decode("utf-8")
        try:
            return json.loads(raw)
        except Exception as e:
            print(f"[WARN] JSON decode error: {e}, raw: {raw!r}")
            return {}

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        # SMARTDNS_AUTH_HTML_GUARD_V1
        # Login page is public; dashboard HTML requires a valid session.
        if path in ("/", "/index.html", "/static/index.html"):
            filename = "index.html" if self._is_authenticated() else "login.html"
            return self._serve_file(
                os.path.join(STATIC_DIR, filename),
                "text/html; charset=utf-8"
            )
        elif path.startswith("/static/"):
            filename = os.path.basename(path)
            file_path = os.path.join(STATIC_DIR, filename)
            mime = "text/plain"
            if filename.endswith(".css"):
                mime = "text/css; charset=utf-8"
            elif filename.endswith(".js"):
                mime = "application/javascript; charset=utf-8"
            elif filename.endswith(".svg"):
                mime = "image/svg+xml"
            elif filename.endswith(".png"):
                mime = "image/png"
            return self._serve_file(file_path, mime)

        # Public API
        if path == "/api/auth/status":
            return self._send_json({"authenticated": self._is_authenticated()})

        # Protected API endpoints
        if not self._is_authenticated():
            return self._send_json({"error": "Unauthorized. Please login."}, 401)

        if path == "/api/stats":
            total_domains = get_blocklist_count()
            dnsdist_active = check_service_status("dnsdist")
            unbound_active = check_service_status("unbound")
            load_avg = [round(x, 2) for x in os.getloadavg()] if hasattr(os, "getloadavg") else [0, 0, 0]
            return self._send_json({
                "total_domains": total_domains,
                "dnsdist_active": dnsdist_active,
                "unbound_active": unbound_active,
                "load_avg": load_avg,
                "metrics": get_system_metrics(),
                "hostname": os.uname().nodename if hasattr(os, "uname") else "Server",
                "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            })

        elif path == "/api/analytics/live":
            return self._send_json(get_live_analytics())

        elif path == "/api/config/dnsdist":
            if not os.path.exists(DNSDIST_CONF):
                return self._send_json({"error": "File /etc/dnsdist/dnsdist.conf not found"}, 404)
            with open(DNSDIST_CONF, "r", encoding="utf-8") as f:
                content = f.read()
            mtime = datetime.fromtimestamp(os.path.getmtime(DNSDIST_CONF)).strftime("%Y-%m-%d %H:%M:%S")
            return self._send_json({
                "path": DNSDIST_CONF,
                "content": content,
                "mtime": mtime,
                "size": len(content)
            })

        elif path == "/api/config/dnsdist/structured":
            if not os.path.exists(DNSDIST_CONF):
                return self._send_json({"error": "File /etc/dnsdist/dnsdist.conf not found"}, 404)
            with open(DNSDIST_CONF, "r", encoding="utf-8") as f:
                content = f.read()
            mtime = datetime.fromtimestamp(os.path.getmtime(DNSDIST_CONF)).strftime("%Y-%m-%d %H:%M:%S")
            structured_data = parse_dnsdist_structured(content)
            structured_data["mtime"] = mtime
            return self._send_json(structured_data)

        elif path == "/api/config/unbound":
            if not os.path.exists(UNBOUND_CONF):
                return self._send_json({"error": f"File {UNBOUND_CONF} not found"}, 404)
            with open(UNBOUND_CONF, "r", encoding="utf-8") as f:
                content = f.read()
            mtime = datetime.fromtimestamp(os.path.getmtime(UNBOUND_CONF)).strftime("%Y-%m-%d %H:%M:%S")
            return self._send_json({
                "path": UNBOUND_CONF,
                "content": content,
                "mtime": mtime,
                "size": len(content)
            })

        elif path == "/api/config/unbound/structured":
            if not os.path.exists(UNBOUND_CONF):
                return self._send_json({"error": f"File {UNBOUND_CONF} not found"}, 404)
            with open(UNBOUND_CONF, "r", encoding="utf-8") as f:
                content = f.read()
            mtime = datetime.fromtimestamp(os.path.getmtime(UNBOUND_CONF)).strftime("%Y-%m-%d %H:%M:%S")
            structured_data = parse_unbound_structured(content)
            structured_data["mtime"] = mtime
            return self._send_json(structured_data)

        elif path == "/api/config/sources":
            if not os.path.exists(SOURCES_TXT):
                return self._send_json({"error": "File /opt/blocklist/sources.txt not found"}, 404)
            with open(SOURCES_TXT, "r", encoding="utf-8") as f:
                content = f.read()
            mtime = datetime.fromtimestamp(os.path.getmtime(SOURCES_TXT)).strftime("%Y-%m-%d %H:%M:%S")
            return self._send_json({
                "path": SOURCES_TXT,
                "content": content,
                "mtime": mtime,
                "size": len(content)
            })

        elif path == "/api/blocklist/search":
            q = query.get("q", [""])[0]
            limit = int(query.get("limit", [100])[0])
            res = search_domains(q, limit=limit)
            return self._send_json(res)

        elif path == "/api/blocklist/count":
            count = get_blocklist_count()
            return self._send_json({"count": count})

        elif path == "/api/blocklist/update/log":
            lines_req = int(query.get("lines", [50])[0])
            log_content = ""
            if os.path.exists(UPDATE_LOG):
                try:
                    res = subprocess.run(["tail", "-n", str(lines_req), UPDATE_LOG], capture_output=True, text=True)
                    log_content = res.stdout
                except Exception as e:
                    log_content = f"Error reading log: {e}"
            return self._send_json({
                "is_running": active_update_job["running"],
                "log": log_content
            })

        elif path == "/api/services":
            services = get_netstat_services()
            return self._send_json({"services": services, "timestamp": time.time()})

        elif path == "/api/querylog":
            lines_req = int(query.get("lines", [100])[0])
            log_path = "/var/log/dnsdist_queries.log"
            log_content = ""
            file_exists = os.path.exists(log_path)
            file_size = os.path.getsize(log_path) if file_exists else 0
            if file_exists:
                try:
                    res = subprocess.run(["tail", "-n", str(lines_req), log_path], capture_output=True, text=True)
                    log_content = res.stdout
                except Exception as e:
                    log_content = f"Error reading log: {e}"
            return self._send_json({
                "exists": file_exists,
                "size_bytes": file_size,
                "lines": [l.strip() for l in log_content.splitlines() if l.strip()]
            })

        elif path == "/api/tools/system-info":
            info = get_tools_system_info()
            return self._send_json(info)

        elif path == "/api/tools/update/log":
            lines_req = int(query.get("lines", [100])[0])
            log_content = ""
            if os.path.exists(MAINTENANCE_LOG):
                try:
                    res = subprocess.run(["tail", "-n", str(lines_req), MAINTENANCE_LOG], capture_output=True, text=True)
                    log_content = res.stdout
                except Exception as e:
                    log_content = f"Error reading maintenance log: {e}"
            return self._send_json({
                "is_running": active_tool_update["running"],
                "status": active_tool_update["status"],
                "type": active_tool_update["type"],
                "start_time": active_tool_update["start_time"],
                "log": log_content
            })

        else:
            return self._send_json({"error": "Not Found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        # Public Login
        if path == "/api/login":
            body = self._read_json_body()
            username = body.get("username", "").strip()
            password = body.get("password", "").strip()
            dnsdist_password = get_dnsdist_web_password()
            if dnsdist_password is None:
                return self._send_json(
                    {"error": "Password DNSDist Web UI tidak ditemukan di /etc/dnsdist/dnsdist.conf."},
                    503
                )

            if (
                username == APP_CONFIG["admin_username"]
                and secrets.compare_digest(password, dnsdist_password)
            ):
                token = secrets.token_hex(24)
                active_sessions.add(token)
                save_sessions(active_sessions)
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Set-Cookie", f"smartdns_session={token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400")
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "token": token}).encode("utf-8"))
            else:
                self._send_json({"error": "Invalid username or password"}, 401)
            return

        # Public Logout
        if path == "/api/logout":
            token = self._get_cookie("smartdns_session")
            if token and token in active_sessions:
                active_sessions.remove(token)
                save_sessions(active_sessions)
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Set-Cookie", "smartdns_session=; Path=/; HttpOnly; Max-Age=0")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True}).encode("utf-8"))
            return

        # Protected endpoints
        if not self._is_authenticated():
            return self._send_json({"error": "Unauthorized. Please login."}, 401)

        if path == "/api/config/dnsdist/test":
            body = self._read_json_body()
            content = body.get("content", "")
            is_ok, message = test_dnsdist_syntax(content)
            return self._send_json({"valid": is_ok, "message": message})

        elif path == "/api/config/dnsdist":
            body = self._read_json_body()
            content = body.get("content", "")
            validate_first = body.get("validate", True)

            if validate_first:
                is_ok, message = test_dnsdist_syntax(content)
                if not is_ok:
                    return self._send_json({
                        "error": "Syntax validation failed. Config was not saved.",
                        "details": message
                    }, 400)

            # Create backup
            try:
                if os.path.exists(DNSDIST_CONF):
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    backup_path = f"{DNSDIST_CONF}.bak_{timestamp}"
                    shutil.copy2(DNSDIST_CONF, backup_path)
                
                # Write new config
                with open(DNSDIST_CONF, "w", encoding="utf-8") as f:
                    f.write(content)

                # Set proper ownership & permissions (root:_dnsdist 640)
                try:
                    shutil.chown(DNSDIST_CONF, user="root", group="_dnsdist")
                except Exception:
                    pass
                os.chmod(DNSDIST_CONF, 0o640)

                return self._send_json({
                    "success": True,
                    "message": "Config saved successfully! Automatic backup created.",
                    "backup": backup_path if 'backup_path' in locals() else None
                })
            except Exception as e:
                return self._send_json({"error": f"Failed to save file: {e}"}, 500)

        elif path == "/api/config/dnsdist/structured":
            body = self._read_json_body()
            if not os.path.exists(DNSDIST_CONF):
                return self._send_json({"error": "File /etc/dnsdist/dnsdist.conf not found"}, 404)

            with open(DNSDIST_CONF, "r", encoding="utf-8") as f:
                orig_content = f.read()

            try:
                new_content = update_dnsdist_structured(orig_content, body)
            except ValueError as ve:
                return self._send_json({"error": str(ve)}, 400)
            except Exception as ex:
                return self._send_json({"error": f"Gagal memproses konfigurasi: {ex}"}, 500)

            # Test syntax before writing
            is_ok, msg = test_dnsdist_syntax(new_content)
            if not is_ok:
                return self._send_json({
                    "error": "Validasi sintaks dnsdist gagal. Perubahan dibatalkan.",
                    "details": msg
                }, 400)

            # Create backup
            try:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                backup_path = f"{DNSDIST_CONF}.bak_{timestamp}"
                shutil.copy2(DNSDIST_CONF, backup_path)

                with open(DNSDIST_CONF, "w", encoding="utf-8") as f:
                    f.write(new_content)

                try:
                    shutil.chown(DNSDIST_CONF, user="root", group="_dnsdist")
                except Exception:
                    pass
                os.chmod(DNSDIST_CONF, 0o640)

                reloaded = False
                reload_msg = ""
                if body.get("auto_reload", True):
                    r = subprocess.run(["systemctl", "restart", "dnsdist"], capture_output=True, text=True)
                    reloaded = (r.returncode == 0)
                    reload_msg = " & service dnsdist berhasil di-restart!" if reloaded else f" (namun restart dnsdist gagal: {r.stderr})"

                # Auto-sync ACL to Unbound if requested
                if body.get("sync_acl", True) and "acl" in body:
                    user_acls = [a.strip() for a in body["acl"] if a.strip()]
                    final_acls = ["127.0.0.0/8", "::1/128"]
                    for a in user_acls:
                        if a not in final_acls:
                            final_acls.append(a)
                    ok_u, msg_u = sync_acl_to_unbound(final_acls)
                    if ok_u:
                        reload_msg += " & ACL otomatis disinkronkan ke Unbound"

                return self._send_json({
                    "success": True,
                    "message": f"Konfigurasi berhasil diperbarui{reload_msg}",
                    "backup": backup_path,
                    "data": parse_dnsdist_structured(new_content)
                })
            except Exception as e:
                return self._send_json({"error": f"Gagal menyimpan file: {e}"}, 500)

        elif path == "/api/config/dnsdist/reload":
            try:
                res = subprocess.run(["systemctl", "restart", "dnsdist"], capture_output=True, text=True)
                if res.returncode == 0:
                    return self._send_json({"success": True, "message": "dnsdist service restarted successfully!"})
                else:
                    return self._send_json({
                        "error": "Failed to restart dnsdist",
                        "details": res.stderr or res.stdout
                    }, 500)
            except Exception as e:
                return self._send_json({"error": str(e)}, 500)

        elif path == "/api/config/unbound/structured":
            body = self._read_json_body()
            if not os.path.exists(UNBOUND_CONF):
                return self._send_json({"error": f"File {UNBOUND_CONF} not found"}, 404)

            with open(UNBOUND_CONF, "r", encoding="utf-8") as f:
                orig_content = f.read()

            try:
                new_content = update_unbound_structured(orig_content, body)
            except ValueError as ve:
                return self._send_json({"error": str(ve)}, 400)
            except Exception as ex:
                return self._send_json({"error": f"Gagal memproses konfigurasi Unbound: {ex}"}, 500)

            # Test syntax before writing
            is_ok, msg = test_unbound_syntax(new_content)
            if not is_ok:
                return self._send_json({
                    "error": "Validasi sintaks Unbound gagal. Perubahan dibatalkan.",
                    "details": msg
                }, 400)

            # Create backup
            try:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                backup_path = f"{UNBOUND_CONF}.bak_{timestamp}"
                shutil.copy2(UNBOUND_CONF, backup_path)

                with open(UNBOUND_CONF, "w", encoding="utf-8") as f:
                    f.write(new_content)
                os.chmod(UNBOUND_CONF, 0o644)

                reloaded = False
                reload_msg = ""
                if body.get("auto_reload", True):
                    r = subprocess.run(["systemctl", "restart", "unbound"], capture_output=True, text=True)
                    reloaded = (r.returncode == 0)
                    reload_msg = " & service unbound berhasil di-restart!" if reloaded else f" (namun restart unbound gagal: {r.stderr})"

                # Sync ACL to dnsdist if requested
                if body.get("sync_acl", True) and "acl" in body:
                    user_acls = [a.strip() for a in body["acl"] if a.strip()]
                    final_acls = ["127.0.0.0/8", "::1/128"]
                    for a in user_acls:
                        if a not in final_acls:
                            final_acls.append(a)
                    ok_d, msg_d = sync_acl_to_dnsdist(final_acls)
                    if ok_d:
                        reload_msg += " & ACL otomatis disinkronkan ke DNSDist"

                return self._send_json({
                    "success": True,
                    "message": f"Konfigurasi Unbound berhasil diperbarui{reload_msg}",
                    "backup": backup_path,
                    "data": parse_unbound_structured(new_content)
                })
            except Exception as e:
                return self._send_json({"error": f"Gagal menyimpan file Unbound: {e}"}, 500)

        elif path == "/api/config/unbound/raw":
            body = self._read_json_body()
            content = body.get("content", "")
            if not os.path.exists(UNBOUND_CONF):
                return self._send_json({"error": f"File {UNBOUND_CONF} not found"}, 404)

            # Test syntax
            is_ok, msg = test_unbound_syntax(content)
            if not is_ok:
                return self._send_json({
                    "error": "Validasi sintaks Unbound gagal. Perubahan dibatalkan.",
                    "details": msg
                }, 400)

            try:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                backup_path = f"{UNBOUND_CONF}.bak_{timestamp}"
                shutil.copy2(UNBOUND_CONF, backup_path)

                with open(UNBOUND_CONF, "w", encoding="utf-8") as f:
                    f.write(content)
                os.chmod(UNBOUND_CONF, 0o644)

                reloaded = False
                reload_msg = ""
                if body.get("auto_reload", True):
                    r = subprocess.run(["systemctl", "restart", "unbound"], capture_output=True, text=True)
                    reloaded = (r.returncode == 0)
                    reload_msg = " & service unbound berhasil di-restart!" if reloaded else f" (namun restart unbound gagal: {r.stderr})"

                return self._send_json({
                    "success": True,
                    "message": f"Konfigurasi Unbound berhasil disimpan!{reload_msg}",
                    "backup": backup_path
                })
            except Exception as e:
                return self._send_json({"error": f"Gagal menyimpan file: {e}"}, 500)

        elif path == "/api/config/unbound/test":
            body = self._read_json_body()
            content = body.get("content", "")
            is_ok, msg = test_unbound_syntax(content)
            return self._send_json({"valid": is_ok, "message": msg})

        elif path == "/api/config/unbound/reload":
            try:
                res = subprocess.run(["systemctl", "restart", "unbound"], capture_output=True, text=True)
                if res.returncode == 0:
                    return self._send_json({"success": True, "message": "unbound service restarted successfully!"})
                else:
                    return self._send_json({
                        "error": "Failed to restart unbound",
                        "details": res.stderr or res.stdout
                    }, 500)
            except Exception as e:
                return self._send_json({"error": str(e)}, 500)


        elif path == "/api/cache/flush":
            ok, out = exec_dnsdist_console('getPool(""):getCache():expunge(0)')
            unbound_flushed = False
            try:
                r_unb = subprocess.run(["unbound-control", "flush_zone", "."], capture_output=True, text=True)
                if r_unb.returncode == 0:
                    unbound_flushed = True
            except Exception:
                pass

            if ok:
                msg = f"DNS Cache dnsdist berhasil dibersihkan ({out} entries dihapus)!"
                if unbound_flushed:
                    msg += " Cache Unbound recurser juga di-flush."
                return self._send_json({"success": True, "message": msg, "expunged": out})
            else:
                return self._send_json({
                    "error": "Gagal membersihkan cache via console dnsdist",
                    "details": out
                }, 500)

        elif path == "/api/querylog/clear":
            log_path = "/var/log/dnsdist_queries.log"
            try:
                if os.path.exists(log_path):
                    with open(log_path, "w", encoding="utf-8") as f:
                        pass
                return self._send_json({"success": True, "message": "Query log berhasil dikosongkan."})
            except Exception as e:
                return self._send_json({"error": f"Gagal menghapus query log: {e}"}, 500)

        elif path == "/api/config/sources":
            body = self._read_json_body()
            content = body.get("content", "")
            try:
                if os.path.exists(SOURCES_TXT):
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    backup_path = f"{SOURCES_TXT}.bak_{timestamp}"
                    shutil.copy2(SOURCES_TXT, backup_path)

                with open(SOURCES_TXT, "w", encoding="utf-8") as f:
                    f.write(content)
                os.chmod(SOURCES_TXT, 0o644)

                return self._send_json({
                    "success": True,
                    "message": "Sources saved successfully!",
                    "backup": backup_path if 'backup_path' in locals() else None
                })
            except Exception as e:
                return self._send_json({"error": f"Failed to save sources: {e}"}, 500)

        elif path == "/api/blocklist/update":
            global active_update_job
            if active_update_job["running"]:
                return self._send_json({"error": "Blocklist update is already in progress."}, 409)

            if not os.path.exists(UPDATE_SCRIPT):
                return self._send_json({"error": f"Script {UPDATE_SCRIPT} not found"}, 404)

            try:
                import threading
                def run_updater():
                    global active_update_job
                    active_update_job["running"] = True
                    active_update_job["start_time"] = time.time()
                    active_update_job["status"] = "running"
                    try:
                        proc = subprocess.Popen(["bash", UPDATE_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        active_update_job["pid"] = proc.pid
                        proc.wait()
                        active_update_job["status"] = "finished"
                    except Exception as ex:
                        print(f"[ERROR] Update process failed: {ex}")
                        active_update_job["status"] = "failed"
                    finally:
                        active_update_job["running"] = False
                        # Reset domain count cache so it recounts
                        cached_domain_count["mtime"] = 0

                t = threading.Thread(target=run_updater, daemon=True)
                t.start()

                return self._send_json({"success": True, "message": "Blocklist update process started in background."})
            except Exception as e:
                return self._send_json({"error": f"Failed to trigger update: {e}"}, 500)

        elif path == "/api/password/change":
            return self._send_json({
                "error": (
                    "Password login SmartDNS UI mengikuti password DNSDist Web UI. "
                    "Ubah password melalui konfigurasi DNSDist."
                )
            }, 409)

        elif path == "/api/tools/exec":
            body = self._read_json_body()
            result = execute_tool_command(body)
            return self._send_json(result)

        elif path == "/api/tools/update":
            body = self._read_json_body()
            update_type = body.get("type", "patch")
            res, code = trigger_system_update(update_type)
            return self._send_json(res, code)

        else:
            return self._send_json({"error": "Not Found"}, 404)

    def _serve_file(self, file_path, content_type):
        if not os.path.exists(file_path):
            self.send_error(404, "File not found")
            return
        try:
            with open(file_path, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self.send_error(500, f"Error reading file: {e}")

    def log_message(self, format, *args):
        # Clean logging
        sys.stderr.write(f"[{datetime.now().strftime('%d/%b/%Y %H:%M:%S')}] {args[0]} - {args[1]} {args[2]}\n")


def run():
    port = int(APP_CONFIG.get("port", 5000))
    host = APP_CONFIG.get("host", "0.0.0.0")
    server_address = (host, port)
    httpd = ThreadingHTTPServer(server_address, SmartDNSHandler)
    print(f"==================================================")
    print(f"  SmartDNS Management UI Server")
    print(f"  Running on http://{host}:{port}")
    print(f"  Admin User: {APP_CONFIG.get('admin_username')}")
    print(f"==================================================")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.server_close()

if __name__ == "__main__":
    run()
