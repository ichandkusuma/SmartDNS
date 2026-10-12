/* ==========================================================================
   SmartDNS Management Dashboard - Interactive Client Application
   ========================================================================== */

let currentTab = 'dashboard';
let searchDebounceTimer = null;
let servicesAutoRefreshTimer = null;
let allServicesCache = [];

document.addEventListener('DOMContentLoaded', () => {
  checkAuth();
  setupKeyboardShortcuts();
});

// --------------------------------------------------------------------------
// Authentication
// --------------------------------------------------------------------------
async function checkAuth() {
  try {
    const res = await fetch('/api/auth/status');
    const data = await res.json();
    if (data.authenticated) {
      showApp();
    } else {
      showLogin();
    }
  } catch (err) {
    showLogin();
  }
}

function showLogin() {
  const modal = document.getElementById('login-modal');
  const app = document.getElementById('app');
  if (modal) modal.classList.remove('hidden');
  if (app) app.classList.add('hidden');
  const password = document.getElementById('password');
  if (password) password.value = '';
}

function showApp() {
  // Halaman login tidak memuat dashboard markup.
  if (!document.getElementById('app')) {
    window.location.replace('/');
    return;
  }
  const modal = document.getElementById('login-modal');
  if (modal) modal.classList.add('hidden');
  document.getElementById('app').classList.remove('hidden');
  
  // Initial data load
  fetchOverviewStats();
  if (!window.smartdnsMetricsTimer) {
    window.smartdnsMetricsTimer = setInterval(() => {
      if (!document.getElementById('app').classList.contains('hidden')) fetchOverviewStats();
    }, 3000);
  }
  fetchStructuredDNSDistConfig();
  fetchDNSDistConfig();
  fetchStructuredUnboundConfig();
  fetchUnboundConfig();
  fetchSourcesConfig();
  fetchServices();
  fetchUpdateLog();
  fetchToolsSystemInfo();

  // Start clock
  setInterval(updateServerClock, 1000);
}

async function handleLogin(e) {
  e.preventDefault();
  const usernameInput = document.getElementById('username');
  const passwordInput = document.getElementById('password');
  const errorBox = document.getElementById('login-error');
  const spinner = document.getElementById('login-spinner');
  const btnText = document.querySelector('#btn-login .btn-text');

  errorBox.classList.add('hidden');
  spinner.classList.remove('hidden');
  btnText.textContent = 'Memverifikasi...';

  try {
    const res = await fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: usernameInput.value,
        password: passwordInput.value
      })
    });
    const data = await res.json();
    if (res.ok && data.success) {
      window.location.replace('/');
    } else {
      errorBox.textContent = data.error || 'Username atau password salah.';
      errorBox.classList.remove('hidden');
    }
  } catch (err) {
    errorBox.textContent = 'Gagal terhubung ke server UI: ' + err.message;
    errorBox.classList.remove('hidden');
  } finally {
    spinner.classList.add('hidden');
    btnText.textContent = 'Masuk ke Dashboard';
  }
}

async function handleLogout() {
  try {
    await fetch('/api/logout', { method: 'POST' });
  } catch (err) {}
  window.location.replace('/');
}

// --------------------------------------------------------------------------
// Tab Navigation
// --------------------------------------------------------------------------
function switchTab(tabId) {
  currentTab = tabId;

  // Update nav items
  document.querySelectorAll('.sidebar-nav .nav-item').forEach(item => {
    item.classList.remove('active');
  });
  const activeBtn = Array.from(document.querySelectorAll('.sidebar-nav .nav-item')).find(btn => {
    return btn.getAttribute('onclick')?.includes(tabId);
  });
  if (activeBtn) activeBtn.classList.add('active');

  // Update tab panes
  document.querySelectorAll('.tab-pane').forEach(pane => {
    pane.classList.remove('active');
  });
  const targetPane = document.getElementById(`tab-${tabId}`);
  if (targetPane) targetPane.classList.add('active');

  // Update Topbar Title
  const titleMap = {
    dashboard: { title: 'System Overview', sub: 'Status layanan SmartDNS dan telemetri langsung' },
    search: { title: 'Pencarian Domain', sub: 'Pengecekan daftar blokir 5.5M+ domain secara instan' },
    dnsdist: { title: 'DNSDist Config Editor', sub: 'Konfigurasi router DNS dan kebijakan spoof /etc/dnsdist/dnsdist.conf' },
    unbound: { title: 'Unbound Resolver Config', sub: 'Konfigurasi resolver rekursif & Domain Insecure /etc/unbound/unbound.conf.d/smartdns.conf' },
    sources: { title: 'Blocklist Sources', sub: 'Kelola URL sumber feed /opt/blocklist/sources.txt' },
    services: { title: 'Active Services Monitor', sub: 'Daftar port dan proses yang sedang berjalan (netstat -ntplu)' },
    analytics: { title: 'Live Analytics & Riwayat Query', sub: 'Statistik performa real-time, upstream resolver, dan query logging' },
    tools: { title: 'Tools & Pemeliharaan SmartDNS', sub: 'Pengujian resolusi DNS, verifikasi konfigurasi, dan pembaruan sistem' }
  };
  const info = titleMap[tabId] || { title: 'Dashboard', sub: '' };
  document.getElementById('page-title').textContent = info.title;
  document.getElementById('page-subtitle').textContent = info.sub;

  // Tab-specific triggers
  if (tabId === 'services') {
    fetchServices();
    startServicesAutoRefresh();
  } else {
    stopServicesAutoRefresh();
  }

  if (tabId === 'analytics') {
    fetchLiveAnalytics();
    fetchQueryLog();
    startAnalyticsAutoRefresh();
  } else {
    stopAnalyticsAutoRefresh();
  }

  if (tabId === 'search') {
    document.getElementById('domain-search-input').focus();
  }

  if (tabId === 'dnsdist') {
    if (currentDNSDistMode === 'form') {
      fetchStructuredDNSDistConfig();
    } else {
      fetchDNSDistConfig();
    }
  }

  if (tabId === 'unbound') {
    if (currentUnboundMode === 'form') {
      fetchStructuredUnboundConfig();
    } else {
      fetchUnboundConfig();
    }
  }

  if (tabId === 'tools') {
    fetchToolsSystemInfo();
  }
}

function refreshCurrentView() {
  if (currentTab === 'dashboard') {
    fetchOverviewStats();
  } else if (currentTab === 'search') {
    fetchTotalCountOnly();
    performDomainSearch();
  } else if (currentTab === 'dnsdist') {
    if (currentDNSDistMode === 'form') {
      fetchStructuredDNSDistConfig();
    } else {
      fetchDNSDistConfig();
    }
  } else if (currentTab === 'unbound') {
    if (currentUnboundMode === 'form') {
      fetchStructuredUnboundConfig();
    } else {
      fetchUnboundConfig();
    }
  } else if (currentTab === 'sources') {
    fetchSourcesConfig();
    fetchUpdateLog();
  } else if (currentTab === 'services') {
    fetchServices();
  } else if (currentTab === 'analytics') {
    fetchLiveAnalytics();
    fetchQueryLog();
  } else if (currentTab === 'tools') {
    fetchToolsSystemInfo();
  }
  showToast('Data diperbarui.', 'success');
}

// --------------------------------------------------------------------------
// Overview Stats & Telemetry
// --------------------------------------------------------------------------
async function fetchOverviewStats() {
  try {
    const res = await fetch('/api/stats');
    if (!res.ok) return;
    const data = await res.json();

    // Total domains
    const countFormatted = Number(data.total_domains).toLocaleString('id-ID');
    document.getElementById('stat-total-domains').textContent = countFormatted;
    document.getElementById('nav-badge-count').textContent = countFormatted;
    document.getElementById('search-total-count').textContent = countFormatted + ' domain';

    // Status pills
    const pillDnsdist = document.getElementById('pill-dnsdist');
    if (data.dnsdist_active) {
      pillDnsdist.innerHTML = '<span class="dot" style="background:#10b981;"></span> dnsdist: ACTIVE';
      document.getElementById('stat-dnsdist-status').innerHTML = '<span class="badge badge-success">ACTIVE (PORT 53)</span>';
    } else {
      pillDnsdist.innerHTML = '<span class="dot" style="background:#f43f5e;"></span> dnsdist: INACTIVE';
      document.getElementById('stat-dnsdist-status').innerHTML = '<span class="badge badge-danger">STOPPED</span>';
    }

    const pillUnbound = document.getElementById('pill-unbound');
    if (data.unbound_active) {
      pillUnbound.innerHTML = '<span class="dot" style="background:#10b981;"></span> unbound: ACTIVE';
      document.getElementById('stat-unbound-status').innerHTML = '<span class="badge badge-success">ACTIVE (PORT 5300)</span>';
    } else {
      pillUnbound.innerHTML = '<span class="dot" style="background:#f43f5e;"></span> unbound: INACTIVE';
      document.getElementById('stat-unbound-status').innerHTML = '<span class="badge badge-danger">STOPPED</span>';
    }

    // Load Average
    if (data.load_avg) {
      document.getElementById('pill-load').textContent = `Load: ${data.load_avg[0]}, ${data.load_avg[1]}, ${data.load_avg[2]}`;
    }

    // Live host resource monitoring
    const m = data.metrics || {};
    const setText = (id, value) => {
      const el = document.getElementById(id);
      if (el) el.textContent = value;
    };
    const setBar = (id, value) => {
      const el = document.getElementById(id);
      if (el) el.style.width = `${Math.max(0, Math.min(100, Number(value) || 0))}%`;
    };
    setText('mon-cpu', `${m.cpu_percent ?? 0}%`);
    setBar('mon-cpu-bar', m.cpu_percent);
    setText('mon-load', `Load: ${(data.load_avg || [0, 0, 0]).join(' · ')}`);
    setText('mon-ram', `${m.ram_percent ?? 0}%`);
    setBar('mon-ram-bar', m.ram_percent);
    setText('mon-ram-detail', `${((m.ram_used_mb || 0)/1024).toFixed(1)} / ${((m.ram_total_mb || 0)/1024).toFixed(1)} GB · Swap ${m.swap_used_mb ?? 0} MB`);
    setText('mon-disk', `${m.disk_percent ?? 0}%`);
    setBar('mon-disk-bar', m.disk_percent);
    setText('mon-disk-detail', `${m.disk_used_gb ?? 0} / ${m.disk_total_gb ?? 0} GB`);
    setText('mon-iowait', `I/O wait ${m.disk_io_wait ?? 0}%`);
    setText('mon-disk-io', `Read ${m.disk_read_mbs ?? 0} MB/s · Write ${m.disk_write_mbs ?? 0} MB/s`);
    setText('mon-network', `RX ${m.rx_mbps ?? 0} / TX ${m.tx_mbps ?? 0} Mbps`);
    setText('mon-interfaces', `Interfaces: ${(m.interfaces || []).join(', ') || 'none detected'}`);
    setText('mon-pps', `RX ${m.rx_pps ?? 0} pps · TX ${m.tx_pps ?? 0} pps`);

    // Hostname
    if (data.hostname) {
      document.getElementById('node-hostname').textContent = data.hostname;
    }
  } catch (err) {
    console.error('Failed to fetch stats:', err);
  }
}

async function fetchTotalCountOnly() {
  try {
    const res = await fetch('/api/blocklist/count');
    const data = await res.json();
    const formatted = Number(data.count).toLocaleString('id-ID');
    document.getElementById('search-total-count').textContent = formatted + ' domain';
    document.getElementById('nav-badge-count').textContent = formatted;
  } catch (err) {}
}

function updateServerClock() {
  const now = new Date();
  document.getElementById('server-clock').textContent = now.toTimeString().split(' ')[0] + ' WIB';
}

// --------------------------------------------------------------------------
// Domain Search
// --------------------------------------------------------------------------
function debounceDomainSearch() {
  const query = document.getElementById('domain-search-input').value.trim();
  const clearBtn = document.getElementById('search-clear-btn');
  if (query.length > 0) {
    clearBtn.classList.remove('hidden');
  } else {
    clearBtn.classList.add('hidden');
  }

  clearTimeout(searchDebounceTimer);
  if (query.length < 2) {
    document.getElementById('search-placeholder').classList.remove('hidden');
    document.getElementById('verdict-card').classList.add('hidden');
    document.getElementById('search-table-wrap').classList.add('hidden');
    return;
  }
  searchDebounceTimer = setTimeout(() => {
    performDomainSearch();
  }, 350);
}

function clearDomainSearch() {
  document.getElementById('domain-search-input').value = '';
  document.getElementById('search-clear-btn').classList.add('hidden');
  document.getElementById('search-placeholder').classList.remove('hidden');
  document.getElementById('verdict-card').classList.add('hidden');
  document.getElementById('search-table-wrap').classList.add('hidden');
  document.getElementById('domain-search-input').focus();
}

async function performDomainSearch() {
  const query = document.getElementById('domain-search-input').value.trim();
  if (!query) return;

  const placeholder = document.getElementById('search-placeholder');
  const verdictCard = document.getElementById('verdict-card');
  const tableWrap = document.getElementById('search-table-wrap');
  const tbody = document.getElementById('domain-results-tbody');
  const resultsCountText = document.getElementById('results-count-text');

  placeholder.classList.add('hidden');

  try {
    const res = await fetch(`/api/blocklist/search?q=${encodeURIComponent(query)}&limit=100`);
    const data = await res.json();

    // Render Verdict Card
    verdictCard.classList.remove('hidden');
    if (data.exact_match) {
      verdictCard.className = 'verdict-card verdict-blocked';
      verdictCard.innerHTML = `
        <div class="verdict-icon">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <line x1="18" y1="6" x2="6" y2="18"></line>
            <line x1="6" y1="6" x2="18" y2="18"></line>
          </svg>
        </div>
        <div>
          <div class="verdict-title">Domain TERBLOKIR (Exact Match Ditemukan!)</div>
          <div class="verdict-desc">Domain <strong>${escapeHtml(data.query)}</strong> terdaftar persis di /opt/blocklist/domains.txt dan dispoof ke landing page.</div>
        </div>
      `;
    } else if (data.matches.length > 0) {
      verdictCard.className = 'verdict-card verdict-blocked';
      verdictCard.innerHTML = `
        <div class="verdict-icon">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <circle cx="12" cy="12" r="10"></circle>
            <line x1="12" y1="8" x2="12" y2="12"></line>
            <line x1="12" y1="16" x2="12.01" y2="16"></line>
          </svg>
        </div>
        <div>
          <div class="verdict-title">Ditemukan ${data.matches.length} Sub-Domain / Domain Serupa</div>
          <div class="verdict-desc">Kata kunci <strong>"${escapeHtml(data.query)}"</strong> cocok dengan beberapa subdomain atau variasi yang terblokir di bawah.</div>
        </div>
      `;
    } else {
      verdictCard.className = 'verdict-card verdict-clean';
      verdictCard.innerHTML = `
        <div class="verdict-icon">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <polyline points="20 6 9 17 4 12"></polyline>
          </svg>
        </div>
        <div>
          <div class="verdict-title">Domain TIDAK DIBLOKIR (Bersih / Bebas)</div>
          <div class="verdict-desc">Domain <strong>"${escapeHtml(data.query)}"</strong> tidak ditemukan dalam database blocklist saat ini.</div>
        </div>
      `;
    }

    // Render Table if matches exist
    if (data.matches.length > 0) {
      tableWrap.classList.remove('hidden');
      resultsCountText.textContent = `Menampilkan ${data.matches.length} baris domain cocok`;
      tbody.innerHTML = data.matches.map((domain, index) => {
        const isExact = domain.toLowerCase() === data.query.toLowerCase();
        const badge = isExact 
          ? '<span class="badge badge-danger">EXACT MATCH</span>' 
          : '<span class="badge badge-accent">SUBSTRING</span>';

        return `
          <tr>
            <td style="color:var(--text-muted);">${index + 1}</td>
            <td class="font-mono ${isExact ? 'text-white font-bold' : ''}">${highlightText(domain, data.query)}</td>
            <td style="text-align: center;">${badge}</td>
            <td style="text-align: right;">
              <button class="btn btn-secondary btn-sm" onclick="copyToClipboard('${escapeHtml(domain)}')">
                Salin
              </button>
            </td>
          </tr>
        `;
      }).join('');
    } else {
      tableWrap.classList.add('hidden');
    }
  } catch (err) {
    showToast('Gagal mencari domain: ' + err.message, 'error');
  }
}

let currentDNSDistMode = 'form';
let structuredConfigState = {
  spoof_ipv4: [],
  spoof_ipv6: [],
  whitelist: [],
  acl: [],
  webserver_password: '',
  webserver_port: '8083'
};

function switchDNSDistMode(mode) {
  currentDNSDistMode = mode;
  const btnForm = document.getElementById('btn-mode-form');
  const btnRaw = document.getElementById('btn-mode-raw');
  const viewForm = document.getElementById('dnsdist-form-view');
  const viewRaw = document.getElementById('dnsdist-raw-view');

  if (mode === 'form') {
    btnForm.classList.add('active');
    btnRaw.classList.remove('active');
    viewForm.classList.remove('hidden');
    viewRaw.classList.add('hidden');
    fetchStructuredDNSDistConfig();
  } else {
    btnRaw.classList.add('active');
    btnForm.classList.remove('active');
    viewRaw.classList.remove('hidden');
    viewForm.classList.add('hidden');
    fetchDNSDistConfig();
  }
}

// --------------------------------------------------------------------------
// DNSDist Structured Form Config
// --------------------------------------------------------------------------
async function fetchStructuredDNSDistConfig() {
  try {
    const res = await fetch('/api/config/dnsdist/structured');
    if (res.status === 401) {
      showLogin();
      return;
    }
    const data = await res.json();
    if (res.ok) {
      structuredConfigState = data;
      document.getElementById('dnsdist-mtime').textContent = 'Terakhir diubah: ' + (data.mtime || '-');

      // Populate IPv4 Spoof
      document.getElementById('cfg-spoof-ipv4').value = (data.spoof_ipv4 || []).join(', ');

      // Populate IPv6 Spoof
      document.getElementById('cfg-spoof-ipv6').value = (data.spoof_ipv6 || []).join(', ');

      // Populate Whitelist
      renderWhitelistTable(structuredConfigState.whitelist || []);

      // Populate ACL
      renderACLTable(structuredConfigState.acl || []);

      // Populate Webserver Password
      document.getElementById('cfg-webserver-password').value = data.webserver_password || '';

      // Update PowerDNS URL link dynamically
      const serverHost = window.location.hostname;
      const powerdnsPort = data.webserver_port || '8083';
      const powerdnsUrl = `http://${serverHost}:${powerdnsPort}`;
      document.getElementById('display-powerdns-url').textContent = powerdnsUrl;
      const btnLink = document.getElementById('btn-open-powerdns');
      if (btnLink) btnLink.href = powerdnsUrl;

      // Populate Server Policy
      if (document.getElementById('cfg-server-policy')) {
        document.getElementById('cfg-server-policy').value = data.server_policy || 'leastOutstanding';
      }

      // Populate Upstream Resolvers
      structuredConfigState.upstream_servers = data.upstream_servers || [];
      renderUpstreamTable(structuredConfigState.upstream_servers);

      // Populate Rate Limit
      const rl = data.rate_limit || { enabled: false, qps: 100, action: 'DropAction' };
      if (document.getElementById('cfg-ratelimit-enable')) {
        document.getElementById('cfg-ratelimit-enable').checked = !!rl.enabled;
        document.getElementById('cfg-ratelimit-qps').value = rl.qps || 100;
        document.getElementById('cfg-ratelimit-action').value = rl.action || 'DropAction';
        toggleRateLimitFields();
      }

      // Populate Custom DNS Override
      structuredConfigState.custom_dns = data.custom_dns || [];
      renderCustomDNSTable(structuredConfigState.custom_dns);

      // Populate SafeSearch
      const ss = data.safesearch || {};
      if (document.getElementById('cfg-safe-google')) {
        document.getElementById('cfg-safe-google').checked = !!ss.google;
        document.getElementById('cfg-safe-bing').checked = !!ss.bing;
        document.getElementById('cfg-safe-youtube').checked = !!ss.youtube;
        document.getElementById('cfg-safe-ddg').checked = !!ss.duckduckgo;
      }

      // Populate Query Logging
      if (document.getElementById('cfg-query-log-enable')) {
        document.getElementById('cfg-query-log-enable').checked = !!data.query_logging;
      }
    } else {
      showToast('Gagal memuat konfigurasi visual: ' + data.error, 'error');
    }
  } catch (err) {
    showToast('Error koneksi saat memuat konfigurasi dnsdist visual: ' + err.message, 'error');
  }
}

function renderWhitelistTable(list) {
  const tbody = document.getElementById('whitelist-items-tbody');
  if (!list || list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="2" class="text-center text-muted">Belum ada domain whitelist</td></tr>`;
    return;
  }
  tbody.innerHTML = list.map((domain, idx) => `
    <tr>
      <td class="font-mono text-cyan">${escapeHtml(domain)}</td>
      <td style="text-align: right;">
        <button type="button" class="btn-del-item" onclick="removeWhitelistDomain(${idx})">Hapus</button>
      </td>
    </tr>
  `).join('');
}

function addWhitelistDomain() {
  const input = document.getElementById('cfg-new-whitelist');
  let val = input.value.trim();
  if (!val) return;
  if (!val.endsWith('.')) {
    val += '.';
  }
  if (!structuredConfigState.whitelist.includes(val)) {
    structuredConfigState.whitelist.push(val);
    renderWhitelistTable(structuredConfigState.whitelist);
    showToast(`Domain ${val} ditambahkan ke daftar whitelist`, 'success');
  } else {
    showToast('Domain sudah ada dalam daftar whitelist', 'error');
  }
  input.value = '';
  input.focus();
}

function removeWhitelistDomain(idx) {
  const removed = structuredConfigState.whitelist.splice(idx, 1);
  renderWhitelistTable(structuredConfigState.whitelist);
  showToast(`Domain ${removed[0]} dihapus dari whitelist`, 'success');
}

function renderACLTable(list) {
  const tbody = document.getElementById('acl-items-tbody');
  // Always ensure defaults are at the top
  const defaults = ["127.0.0.0/8", "::1/128"];
  const combined = [...defaults];
  list.forEach(item => {
    if (!combined.includes(item)) combined.push(item);
  });
  structuredConfigState.acl = combined;

  tbody.innerHTML = combined.map((prefix, idx) => {
    const isDefault = (idx === 0 || idx === 1 || prefix === '127.0.0.0/8' || prefix === '::1/128');
    const badge = isDefault 
      ? '<span class="lock-badge">🔒 Default Wajib</span>' 
      : '<span class="badge badge-accent">Custom CIDR</span>';
    const action = isDefault 
      ? '<span class="text-muted text-sm" title="Default sistem tidak bisa dihapus">-</span>' 
      : `<button type="button" class="btn-del-item" onclick="removeACLPrefix(${idx})">Hapus</button>`;

    return `
      <tr>
        <td class="font-mono text-white">${escapeHtml(prefix)}</td>
        <td style="text-align: center;">${badge}</td>
        <td style="text-align: right;">${action}</td>
      </tr>
    `;
  }).join('');
}

function addACLPrefix() {
  const input = document.getElementById('cfg-new-acl');
  const val = input.value.trim();
  if (!val) return;
  if (!structuredConfigState.acl.includes(val)) {
    structuredConfigState.acl.push(val);
    renderACLTable(structuredConfigState.acl);
    showToast(`Prefix ${val} ditambahkan ke daftar ACL`, 'success');
  } else {
    showToast('Prefix sudah ada dalam daftar ACL', 'error');
  }
  input.value = '';
  input.focus();
}

function removeACLPrefix(idx) {
  const prefix = structuredConfigState.acl[idx];
  if (prefix === '127.0.0.0/8' || prefix === '::1/128' || idx < 2) {
    showToast('Baris 1 dan 2 (127.0.0.0/8 & ::1/128) adalah default dan tidak dapat dihapus!', 'error');
    return;
  }
  structuredConfigState.acl.splice(idx, 1);
  renderACLTable(structuredConfigState.acl);
  showToast(`Prefix ${prefix} dihapus dari ACL`, 'success');
}

function togglePasswordVisibility(inputId) {
  const el = document.getElementById(inputId);
  if (el.type === 'password') {
    el.type = 'text';
  } else {
    el.type = 'password';
  }
}

async function saveStructuredDNSDistConfig() {
  const btn = document.getElementById('btn-save-structured');
  const rawIPv4 = document.getElementById('cfg-spoof-ipv4').value;
  const rawIPv6 = document.getElementById('cfg-spoof-ipv6').value;
  const newPassword = document.getElementById('cfg-webserver-password').value.trim();
  const autoReload = document.getElementById('cfg-auto-reload').checked;

  // Parse comma separated IPs
  const ips_v4 = rawIPv4.split(',').map(s => s.trim()).filter(s => s.length > 0);
  const ips_v6 = rawIPv6.split(',').map(s => s.trim()).filter(s => s.length > 0);

  if (ips_v4.length === 0) {
    showToast('Harap masukkan minimal 1 IPv4 Spoof Action', 'error');
    return;
  }
  if (ips_v6.length === 0) {
    showToast('Harap masukkan minimal 1 IPv6 Spoof Action', 'error');
    return;
  }
  if (!newPassword) {
    showToast('Password Web Panel tidak boleh kosong', 'error');
    return;
  }

  btn.disabled = true;
  btn.innerHTML = '<span>Menyimpan &amp; Memvalidasi...</span>';

  const payload = {
    spoof_ipv4: ips_v4,
    spoof_ipv6: ips_v6,
    whitelist: structuredConfigState.whitelist,
    acl: structuredConfigState.acl,
    webserver_password: newPassword,
    rate_limit: {
      enabled: document.getElementById('cfg-ratelimit-enable') ? document.getElementById('cfg-ratelimit-enable').checked : false,
      qps: document.getElementById('cfg-ratelimit-qps') ? parseInt(document.getElementById('cfg-ratelimit-qps').value) || 100 : 100,
      action: document.getElementById('cfg-ratelimit-action') ? document.getElementById('cfg-ratelimit-action').value : 'DropAction'
    },
    server_policy: document.getElementById('cfg-server-policy') ? document.getElementById('cfg-server-policy').value : 'leastOutstanding',
    upstream_servers: structuredConfigState.upstream_servers || [],
    custom_dns: structuredConfigState.custom_dns || [],
    safesearch: {
      google: document.getElementById('cfg-safe-google') ? document.getElementById('cfg-safe-google').checked : false,
      bing: document.getElementById('cfg-safe-bing') ? document.getElementById('cfg-safe-bing').checked : false,
      youtube: document.getElementById('cfg-safe-youtube') ? document.getElementById('cfg-safe-youtube').checked : false,
      duckduckgo: document.getElementById('cfg-safe-ddg') ? document.getElementById('cfg-safe-ddg').checked : false
    },
    query_logging: document.getElementById('cfg-query-log-enable') ? document.getElementById('cfg-query-log-enable').checked : false,
    sync_acl: document.getElementById('cfg-sync-acl') ? document.getElementById('cfg-sync-acl').checked : true,
    auto_reload: autoReload
  };

  try {
    const res = await fetch('/api/config/dnsdist/structured', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await res.json();

    if (res.ok && data.success) {
      showToast(data.message, 'success');
      fetchStructuredDNSDistConfig();
      fetchStructuredUnboundConfig();
      fetchOverviewStats();
    } else {
      showToast(data.error || 'Gagal menyimpan konfigurasi.', 'error');
      if (data.details) {
        alert('Detail Kesalahan:\n' + data.details);
      }
    }
  } catch (err) {
    showToast('Gagal menghubungi server: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path>
        <polyline points="17 21 17 13 7 13 7 21"></polyline>
      </svg>
      <span>Simpan &amp; Terapkan Pengaturan</span>
    `;
  }
}

// --------------------------------------------------------------------------
// Flush DNS Cache
// --------------------------------------------------------------------------
async function flushDNSCache() {
  const btn = document.getElementById('btn-flush-cache');
  if (btn) btn.disabled = true;
  showToast('Membersihkan DNS cache...', 'info');
  try {
    const res = await fetch('/api/cache/flush', { method: 'POST' });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast(data.message, 'success');
      if (currentTab === 'analytics') {
        fetchLiveAnalytics();
      }
    } else {
      showToast('Gagal membersihkan cache: ' + (data.error || data.details), 'error');
    }
  } catch (err) {
    showToast('Error koneksi: ' + err.message, 'error');
  } finally {
    if (btn) btn.disabled = false;
  }
}

// --------------------------------------------------------------------------
// Rate Limiting Helper
// --------------------------------------------------------------------------
function toggleRateLimitFields() {
  const checkbox = document.getElementById('cfg-ratelimit-enable');
  const container = document.getElementById('ratelimit-fields');
  if (!checkbox || !container) return;
  const enabled = checkbox.checked;
  container.style.opacity = enabled ? '1' : '0.4';
  container.querySelectorAll('input, select').forEach(el => el.disabled = !enabled);
}

// --------------------------------------------------------------------------
// Upstream Resolvers Handlers
// --------------------------------------------------------------------------
function renderUpstreamTable(servers) {
  const tbody = document.getElementById('upstream-items-tbody');
  if (!tbody) return;
  if (!servers || servers.length === 0) {
    tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">Belum ada upstream resolver</td></tr>';
    return;
  }
  tbody.innerHTML = servers.map((srv, idx) => `
    <tr>
      <td class="font-mono text-cyan">${escapeHtml(srv.name || '-')}</td>
      <td class="font-mono text-white">${escapeHtml(srv.address || '')}</td>
      <td class="font-mono text-muted text-sm">${escapeHtml(srv.checkName || '-')}</td>
      <td style="text-align: right;">
        <button type="button" class="btn-del-item" onclick="removeUpstreamServer(${idx})">Hapus</button>
      </td>
    </tr>
  `).join('');
}

function addUpstreamServer() {
  const nameInput = document.getElementById('cfg-new-srv-name');
  const addrInput = document.getElementById('cfg-new-srv-addr');
  const checkInput = document.getElementById('cfg-new-srv-check');
  const toInput = document.getElementById('cfg-new-srv-timeout');

  const addr = addrInput.value.trim();
  if (!addr) {
    showToast('Alamat IP & port upstream wajib diisi (contoh: 1.1.1.1:53)', 'error');
    return;
  }

  const name = nameInput.value.trim() || addr.replace(/[\.:]/g, '_');
  let check = checkInput.value.trim();
  if (check && !check.endsWith('.')) check += '.';
  const timeout = parseInt(toInput.value) || 2;

  if (!structuredConfigState.upstream_servers) {
    structuredConfigState.upstream_servers = [];
  }

  if (structuredConfigState.upstream_servers.some(s => s.address === addr)) {
    showToast('Alamat upstream sudah ada dalam daftar', 'error');
    return;
  }

  structuredConfigState.upstream_servers.push({
    name: name,
    address: addr,
    checkName: check,
    timeout: timeout
  });

  renderUpstreamTable(structuredConfigState.upstream_servers);
  showToast(`Upstream ${name} (${addr}) ditambahkan`, 'success');

  nameInput.value = '';
  addrInput.value = '';
  checkInput.value = '';
  toInput.value = '2';
}

function removeUpstreamServer(idx) {
  if (structuredConfigState.upstream_servers.length <= 1) {
    if (!confirm('Peringatan: Menghapus seluruh upstream dapat menyebabkan SmartDNS tidak bisa me-resolve query normal. Lanjutkan?')) {
      return;
    }
  }
  const removed = structuredConfigState.upstream_servers.splice(idx, 1);
  renderUpstreamTable(structuredConfigState.upstream_servers);
  showToast(`Upstream ${removed[0].name || removed[0].address} dihapus`, 'success');
}

// --------------------------------------------------------------------------
// Custom DNS Override Handlers
// --------------------------------------------------------------------------
function renderCustomDNSTable(records) {
  const tbody = document.getElementById('customdns-items-tbody');
  if (!tbody) return;
  if (!records || records.length === 0) {
    tbody.innerHTML = '<tr><td colspan="3" class="text-center text-muted">Belum ada record custom DNS</td></tr>';
    return;
  }
  tbody.innerHTML = records.map((rec, idx) => `
    <tr>
      <td class="font-mono text-cyan">${escapeHtml(rec.domain)}</td>
      <td class="font-mono text-white">${escapeHtml(rec.ip)}</td>
      <td style="text-align: right;">
        <button type="button" class="btn-del-item" onclick="removeCustomDNSRecord(${idx})">Hapus</button>
      </td>
    </tr>
  `).join('');
}

function addCustomDNSRecord() {
  const dInput = document.getElementById('cfg-new-custom-domain');
  const ipInput = document.getElementById('cfg-new-custom-ip');

  let domain = dInput.value.trim();
  const ip = ipInput.value.trim();

  if (!domain || !ip) {
    showToast('Domain dan IP tujuan wajib diisi', 'error');
    return;
  }
  if (!domain.endsWith('.')) domain += '.';

  if (!structuredConfigState.custom_dns) {
    structuredConfigState.custom_dns = [];
  }

  if (structuredConfigState.custom_dns.some(r => r.domain.toLowerCase() === domain.toLowerCase())) {
    showToast(`Domain ${domain} sudah ada di daftar override`, 'error');
    return;
  }

  structuredConfigState.custom_dns.push({ domain, ip });
  renderCustomDNSTable(structuredConfigState.custom_dns);
  showToast(`Override ${domain} -> ${ip} ditambahkan`, 'success');

  dInput.value = '';
  ipInput.value = '';
  dInput.focus();
}

function removeCustomDNSRecord(idx) {
  const removed = structuredConfigState.custom_dns.splice(idx, 1);
  renderCustomDNSTable(structuredConfigState.custom_dns);
  showToast(`Record ${removed[0].domain} dihapus`, 'success');
}

// --------------------------------------------------------------------------
// Live Analytics & Query Log Handlers
// --------------------------------------------------------------------------
let analyticsTimer = null;

function startAnalyticsAutoRefresh() {
  stopAnalyticsAutoRefresh();
  analyticsTimer = setInterval(() => {
    if (currentTab === 'analytics') {
      fetchLiveAnalytics();
      fetchQueryLog();
    }
  }, 5000);
}

function stopAnalyticsAutoRefresh() {
  if (analyticsTimer) {
    clearInterval(analyticsTimer);
    analyticsTimer = null;
  }
}

async function fetchLiveAnalytics() {
  try {
    const res = await fetch('/api/analytics/live');
    if (res.status === 401) {
      showLogin();
      return;
    }
    const data = await res.json();
    if (!res.ok) return;

    const stats = data.stats || {};
    const totalQueries = stats['queries'] || 0;
    const cacheHits = stats['cache-hits'] || 0;
    const cacheMisses = stats['cache-misses'] || 0;
    const latencyAvg = stats['latency-avg100'] ? (stats['latency-avg100'] / 1000).toFixed(2) : '0';

    const totalCacheLookup = cacheHits + cacheMisses;
    const hitRatio = totalCacheLookup > 0 ? ((cacheHits / totalCacheLookup) * 100).toFixed(1) : '0.0';

    const elTotal = document.getElementById('ana-total-queries');
    if (elTotal) elTotal.textContent = Number(totalQueries).toLocaleString('id-ID');
    const elRatio = document.getElementById('ana-cache-ratio');
    if (elRatio) elRatio.textContent = hitRatio + '%';
    const elHitsMeta = document.getElementById('ana-cache-hits-meta');
    if (elHitsMeta) elHitsMeta.textContent = `${Number(cacheHits).toLocaleString('id-ID')} Hits / ${Number(cacheMisses).toLocaleString('id-ID')} Misses`;
    const elLat = document.getElementById('ana-avg-latency');
    if (elLat) elLat.textContent = latencyAvg + ' ms';

    // Upstream Servers Table
    const srvTbody = document.getElementById('live-servers-tbody');
    if (srvTbody) {
      const servers = data.servers || [];
      if (servers.length === 0) {
        srvTbody.innerHTML = '<tr><td colspan="8" class="text-center py-4 text-muted">Tidak ada backend resolver terdeteksi</td></tr>';
      } else {
        srvTbody.innerHTML = servers.map(s => {
          const isUp = (s.state || '').toLowerCase() === 'up';
          const badge = isUp 
            ? '<span class="badge badge-success">UP</span>' 
            : '<span class="badge badge-danger">DOWN</span>';
          return `
            <tr>
              <td class="font-mono text-muted">${escapeHtml(s.id)}</td>
              <td class="font-medium text-white">${escapeHtml(s.name)}</td>
              <td class="font-mono text-cyan">${escapeHtml(s.address)}</td>
              <td style="text-align: center;">${badge}</td>
              <td class="font-mono" style="text-align: right;">${s.qps}</td>
              <td class="font-mono" style="text-align: right;">${s.latency} ms</td>
              <td class="font-mono" style="text-align: right;">${Number(s.queries).toLocaleString('id-ID')}</td>
              <td class="font-mono text-muted" style="text-align: right;">${Number(s.drops).toLocaleString('id-ID')}</td>
            </tr>
          `;
        }).join('');
      }
    }

    // Top Queries
    const qTbody = document.getElementById('top-queries-tbody');
    if (qTbody) {
      const topQ = data.top_queries || [];
      if (topQ.length === 0) {
        qTbody.innerHTML = '<tr><td colspan="4" class="text-center py-3 text-muted">Belum ada statistik query</td></tr>';
      } else {
        qTbody.innerHTML = topQ.map((q, idx) => `
          <tr>
            <td class="font-mono text-muted">${idx + 1}</td>
            <td class="font-mono text-cyan text-sm">${escapeHtml(q.domain)}</td>
            <td class="font-mono" style="text-align: right;">${Number(q.count).toLocaleString('id-ID')}</td>
            <td class="font-mono text-muted text-sm" style="text-align: right;">${escapeHtml(q.pct)}</td>
          </tr>
        `).join('');
      }
    }

    // Top Responses
    const rTbody = document.getElementById('top-responses-tbody');
    if (rTbody) {
      const topR = data.top_responses || [];
      if (topR.length === 0) {
        rTbody.innerHTML = '<tr><td colspan="4" class="text-center py-3 text-muted">Belum ada statistik respons</td></tr>';
      } else {
        rTbody.innerHTML = topR.map((r, idx) => `
          <tr>
            <td class="font-mono text-muted">${idx + 1}</td>
            <td class="font-mono text-emerald text-sm">${escapeHtml(r.domain)}</td>
            <td class="font-mono" style="text-align: right;">${Number(r.count).toLocaleString('id-ID')}</td>
            <td class="font-mono text-muted text-sm" style="text-align: right;">${escapeHtml(r.pct)}</td>
          </tr>
        `).join('');
      }
    }

  } catch (err) {
    console.error('Failed to fetch live analytics:', err);
  }
}

async function fetchQueryLog() {
  const select = document.getElementById('querylog-lines-select');
  const lines = select ? select.value : 100;
  try {
    const res = await fetch(`/api/querylog?lines=${lines}`);
    if (!res.ok) return;
    const data = await res.json();

    const viewer = document.getElementById('querylog-viewer');
    const sizeBadge = document.getElementById('querylog-size-badge');
    const notice = document.getElementById('querylog-status-notice');

    if (!data.exists) {
      if (viewer) viewer.textContent = 'File log /var/log/dnsdist_queries.log belum dibuat. Aktifkan fitur "Pencatatan Riwayat Query (Query Log)" di tab DNSDist Config untuk mulai mencatat query.';
      if (sizeBadge) sizeBadge.textContent = 'File tidak ada';
      if (notice) notice.textContent = 'Status: Query logging belum aktif di konfigurasi dnsdist.';
      return;
    }

    const kb = (data.size_bytes / 1024).toFixed(1);
    if (sizeBadge) sizeBadge.textContent = `${kb} KB`;

    if (viewer) {
      if (data.lines && data.lines.length > 0) {
        viewer.textContent = data.lines.join('\n');
        if (notice) notice.textContent = `Menampilkan ${data.lines.length} baris log query terbaru.`;
      } else {
        viewer.textContent = '(Log file kosong - belum ada query baru tercatat)';
        if (notice) notice.textContent = 'File log ada namun belum berisi riwayat query.';
      }
      viewer.scrollTop = viewer.scrollHeight;
    }
  } catch (err) {
    console.error('Failed to fetch query log:', err);
  }
}

async function clearQueryLog() {
  if (!confirm('Apakah Anda yakin ingin mengosongkan file log riwayat query (/var/log/dnsdist_queries.log)?')) return;
  try {
    const res = await fetch('/api/querylog/clear', { method: 'POST' });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast(data.message, 'success');
      fetchQueryLog();
    } else {
      showToast('Gagal mengosongkan query log: ' + data.error, 'error');
    }
  } catch (err) {
    showToast('Error koneksi: ' + err.message, 'error');
  }
}

// --------------------------------------------------------------------------
// DNSDist Config Editor (Raw Mode)
// --------------------------------------------------------------------------
async function fetchDNSDistConfig() {
  try {
    const res = await fetch('/api/config/dnsdist');
    const data = await res.json();
    if (res.ok) {
      document.getElementById('dnsdist-editor').value = data.content;
      document.getElementById('dnsdist-mtime').textContent = 'Terakhir diubah: ' + data.mtime;
    } else {
      showToast('Gagal memuat config dnsdist: ' + data.error, 'error');
    }
  } catch (err) {
    showToast('Error koneksi saat memuat config dnsdist', 'error');
  }
}

async function testDNSDistSyntax() {
  const content = document.getElementById('dnsdist-editor').value;
  const banner = document.getElementById('dnsdist-syntax-banner');
  const btn = document.getElementById('btn-test-dnsdist');

  btn.disabled = true;
  btn.innerHTML = '<span>Menguji Sintaks...</span>';

  try {
    const res = await fetch('/api/config/dnsdist/test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content })
    });
    const data = await res.json();

    banner.classList.remove('hidden');
    if (data.valid) {
      banner.className = 'alert-box success mt-3';
      banner.innerHTML = `<strong>Sintaks Valid!</strong> ${escapeHtml(data.message || 'Konfigurasi dnsdist siap dan bebas dari kesalahan sintaks.')}`;
      showToast('Uji sintaks berhasil: Konfigurasi VALID!', 'success');
    } else {
      banner.className = 'alert-box error mt-3';
      banner.innerHTML = `<strong>Sintaks Error Ditemukan:</strong><pre class="font-mono mt-2">${escapeHtml(data.message)}</pre>`;
      showToast('Konfigurasi memiliki kesalahan sintaks.', 'error');
    }
  } catch (err) {
    showToast('Gagal menguji sintaks: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="20 6 9 17 4 12"></polyline>
      </svg>
      <span>Uji Sintaks (Check)</span>
    `;
  }
}

async function saveDNSDistConfig() {
  const content = document.getElementById('dnsdist-editor').value;
  const btn = document.getElementById('btn-save-dnsdist');
  const banner = document.getElementById('dnsdist-syntax-banner');

  if (!confirm('Simpan perubahan ke /etc/dnsdist/dnsdist.conf?\nCadangan otomatis akan dibuat.')) {
    return;
  }

  btn.disabled = true;
  btn.innerHTML = '<span>Menyimpan...</span>';

  try {
    const res = await fetch('/api/config/dnsdist', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content, validate: true })
    });
    const data = await res.json();

    if (res.ok && data.success) {
      banner.classList.add('hidden');
      showToast(data.message, 'success');
      fetchDNSDistConfig();
    } else {
      banner.classList.remove('hidden');
      banner.className = 'alert-box error mt-3';
      banner.innerHTML = `<strong>Gagal Menyimpan:</strong> ${escapeHtml(data.error)}<pre class="font-mono mt-2">${escapeHtml(data.details || '')}</pre>`;
      showToast('Gagal menyimpan konfigurasi.', 'error');
    }
  } catch (err) {
    showToast('Koneksi terputus saat menyimpan: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path>
        <polyline points="17 21 17 13 7 13 7 21"></polyline>
      </svg>
      <span>Simpan Perubahan</span>
    `;
  }
}

async function reloadDNSDistService() {
  const btn = document.getElementById('btn-reload-dnsdist');
  btn.disabled = true;
  btn.innerHTML = '<span>Reloading...</span>';

  try {
    const res = await fetch('/api/config/dnsdist/reload', { method: 'POST' });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast('DNSDist service berhasil direload!', 'success');
      fetchOverviewStats();
    } else {
      showToast('Gagal reload DNSDist: ' + (data.details || data.error), 'error');
    }
  } catch (err) {
    showToast('Gagal memanggil API reload: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M23 4v6h-6"></path>
        <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"></path>
      </svg>
      <span>Reload Service</span>
    `;
  }
}

function copyDNSDistContent() {
  const content = document.getElementById('dnsdist-editor').value;
  copyToClipboard(content, 'Seluruh isi konfigurasi dnsdist berhasil disalin!');
}

// --------------------------------------------------------------------------
// Unbound Resolver Configuration Handlers
// --------------------------------------------------------------------------
let currentUnboundMode = 'form';
let unboundStructuredState = {
  domain_insecure: [],
  acl: [],
  port: 5300,
  interfaces: [],
  do_ip4: true,
  do_ip6: false,
  do_udp: true,
  do_tcp: true,
  prefetch: true,
  prefetch_key: true,
  qname_minimisation: true,
  serve_expired: true,
  cache_min_ttl: 60,
  cache_max_ttl: 86400,
  serve_expired_ttl: 86400,
  num_threads: 8,
  rrset_cache_size: "512m",
  msg_cache_size: "256m",
  so_reuseport: true,
  edns_buffer_size: 1232,
  verbosity: 1,
  log_queries: false,
  log_replies: false
};
let currentInsecureFilter = '';

function switchUnboundMode(mode) {
  currentUnboundMode = mode;
  const btnForm = document.getElementById('btn-unbound-mode-form');
  const btnRaw = document.getElementById('btn-unbound-mode-raw');
  const viewForm = document.getElementById('unbound-form-view');
  const viewRaw = document.getElementById('unbound-raw-view');

  if (mode === 'form') {
    if (btnForm) btnForm.classList.add('active');
    if (btnRaw) btnRaw.classList.remove('active');
    if (viewForm) viewForm.classList.remove('hidden');
    if (viewRaw) viewRaw.classList.add('hidden');
    fetchStructuredUnboundConfig();
  } else {
    if (btnRaw) btnRaw.classList.add('active');
    if (btnForm) btnForm.classList.remove('active');
    if (viewRaw) viewRaw.classList.remove('hidden');
    if (viewForm) viewForm.classList.add('hidden');
    fetchUnboundConfig();
  }
}

async function fetchStructuredUnboundConfig() {
  try {
    const res = await fetch('/api/config/unbound/structured');
    if (res.status === 401) {
      showLogin();
      return;
    }
    const data = await res.json();
    if (res.ok) {
      unboundStructuredState = data;
      const mtimeEl = document.getElementById('unbound-mtime');
      if (mtimeEl) mtimeEl.textContent = 'Terakhir diubah: ' + (data.mtime || '-');
      renderUnboundForm(data);
    } else {
      showToast('Gagal memuat konfigurasi visual Unbound: ' + data.error, 'error');
    }
  } catch (err) {
    showToast('Error koneksi saat memuat konfigurasi Unbound: ' + err.message, 'error');
  }
}

function renderUnboundForm(data) {
  // 1. Domain Insecure
  renderDomainInsecureTable(data.domain_insecure || [], currentInsecureFilter);

  // 2. ACL
  renderUnboundACLTable(data.acl || []);
}


// Domain Insecure Table & Filter
function renderDomainInsecureTable(list, filter = '') {
  const tbody = document.getElementById('unbound-insecure-tbody');
  const countBadge = document.getElementById('unbound-insecure-count');
  if (countBadge) {
    countBadge.textContent = `${list.length} Domain`;
  }
  if (!tbody) return;

  const f = (filter || '').trim().toLowerCase();
  const filteredIndices = [];
  list.forEach((dom, idx) => {
    if (!f || dom.toLowerCase().includes(f)) {
      filteredIndices.push(idx);
    }
  });

  if (filteredIndices.length === 0) {
    const msg = f ? `Tidak ada domain yang cocok dengan pencarian "${escapeHtml(f)}"` : 'Belum ada domain insecure yang didaftarkan';
    tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-3">${msg}</td></tr>`;
    return;
  }

  tbody.innerHTML = filteredIndices.map(origIdx => {
    const domain = list[origIdx];
    return `
      <tr>
        <td class="font-mono text-muted text-sm">${origIdx + 1}</td>
        <td class="font-mono text-cyan font-medium">${escapeHtml(domain)}</td>
        <td style="text-align: center;"><span class="badge badge-accent">domain-insecure</span></td>
        <td style="text-align: right;">
          <button type="button" class="btn-del-item" onclick="removeDomainInsecure(${origIdx})">Hapus</button>
        </td>
      </tr>
    `;
  }).join('');
}

function filterDomainInsecure(keyword) {
  currentInsecureFilter = keyword;
  renderDomainInsecureTable(unboundStructuredState.domain_insecure || [], keyword);
}

function addDomainInsecure() {
  const input = document.getElementById('unbound-new-insecure');
  let val = input.value.trim().toLowerCase().replace(/^["']|["']$/g, '').replace(/\.$/, '');
  if (!val) return;

  if (!unboundStructuredState.domain_insecure) {
    unboundStructuredState.domain_insecure = [];
  }

  if (unboundStructuredState.domain_insecure.includes(val)) {
    showToast(`Domain ${val} sudah ada di daftar insecure`, 'error');
    return;
  }

  unboundStructuredState.domain_insecure.push(val);
  renderDomainInsecureTable(unboundStructuredState.domain_insecure, currentInsecureFilter);
  showToast(`Domain ${val} ditambahkan ke Domain Insecure (Bypass DNSSEC)`, 'success');
  input.value = '';
  input.focus();
}

function removeDomainInsecure(idx) {
  if (!unboundStructuredState.domain_insecure) return;
  const removed = unboundStructuredState.domain_insecure.splice(idx, 1);
  renderDomainInsecureTable(unboundStructuredState.domain_insecure, currentInsecureFilter);
  showToast(`Domain ${removed[0]} dihapus dari Domain Insecure`, 'success');
}

function toggleBulkInsecureModal() {
  const box = document.getElementById('unbound-bulk-insecure-box');
  if (!box) return;
  box.classList.toggle('hidden');
  if (!box.classList.contains('hidden')) {
    const ta = document.getElementById('unbound-bulk-insecure-input');
    if (ta) {
      ta.value = '';
      ta.focus();
    }
  }
}

function applyBulkDomainInsecure() {
  const ta = document.getElementById('unbound-bulk-insecure-input');
  if (!ta) return;
  const rawText = ta.value;
  const tokens = rawText.split(/[\r\n,\s]+/);
  let addedCount = 0;

  if (!unboundStructuredState.domain_insecure) {
    unboundStructuredState.domain_insecure = [];
  }

  tokens.forEach(tok => {
    let clean = tok.trim().toLowerCase().replace(/^["']|["']$/g, '').replace(/\.$/, '');
    if (clean && clean.includes('.') && !unboundStructuredState.domain_insecure.includes(clean)) {
      unboundStructuredState.domain_insecure.push(clean);
      addedCount++;
    }
  });

  renderDomainInsecureTable(unboundStructuredState.domain_insecure, currentInsecureFilter);
  toggleBulkInsecureModal();
  if (addedCount > 0) {
    showToast(`Berhasil menambahkan ${addedCount} domain insecure baru!`, 'success');
  } else {
    showToast('Tidak ada domain baru yang ditambahkan (mungkin duplikat atau format tidak valid).', 'info');
  }
}

// Unbound ACL Handlers
function renderUnboundACLTable(list) {
  const tbody = document.getElementById('unbound-acl-tbody');
  if (!tbody) return;
  const defaults = ["127.0.0.0/8", "::1/128"];
  const combined = [...defaults];
  list.forEach(item => {
    if (!combined.includes(item)) combined.push(item);
  });
  unboundStructuredState.acl = combined;

  tbody.innerHTML = combined.map((prefix, idx) => {
    const isDefault = (idx === 0 || idx === 1 || prefix === '127.0.0.0/8' || prefix === '::1/128');
    const badge = isDefault 
      ? '<span class="lock-badge">🔒 Localhost Wajib</span>' 
      : '<span class="badge badge-accent">Allow Prefix</span>';
    const action = isDefault 
      ? '<span class="text-muted text-sm">-</span>' 
      : `<button type="button" class="btn-del-item" onclick="removeUnboundACL(${idx})">Hapus</button>`;

    return `
      <tr>
        <td class="font-mono text-white">${escapeHtml(prefix)}</td>
        <td style="text-align: center;">${badge}</td>
        <td style="text-align: right;">${action}</td>
      </tr>
    `;
  }).join('');
}

function addUnboundACL() {
  const input = document.getElementById('unbound-new-acl');
  const val = input.value.trim();
  if (!val) return;
  if (!unboundStructuredState.acl.includes(val)) {
    unboundStructuredState.acl.push(val);
    renderUnboundACLTable(unboundStructuredState.acl);
    showToast(`Prefix ${val} ditambahkan ke ACL Unbound`, 'success');
  } else {
    showToast('Prefix sudah ada dalam daftar ACL Unbound', 'error');
  }
  input.value = '';
  input.focus();
}

function removeUnboundACL(idx) {
  const prefix = unboundStructuredState.acl[idx];
  if (prefix === '127.0.0.0/8' || prefix === '::1/128' || idx < 2) {
    showToast('Baris 1 dan 2 (127.0.0.0/8 & ::1/128) adalah default dan tidak dapat dihapus!', 'error');
    return;
  }
  unboundStructuredState.acl.splice(idx, 1);
  renderUnboundACLTable(unboundStructuredState.acl);
  showToast(`Prefix ${prefix} dihapus dari ACL Unbound`, 'success');
}

// Save Structured Unbound
async function saveStructuredUnboundConfig() {
  const btn = document.getElementById('btn-save-unbound-structured');
  btn.disabled = true;
  btn.innerHTML = '<span>Menyimpan &amp; Memvalidasi...</span>';

  const syncAcl = document.getElementById('unbound-cfg-sync-acl') ? document.getElementById('unbound-cfg-sync-acl').checked : true;
  const autoReload = document.getElementById('unbound-cfg-auto-reload') ? document.getElementById('unbound-cfg-auto-reload').checked : true;

  const payload = {
    domain_insecure: unboundStructuredState.domain_insecure || [],
    acl: unboundStructuredState.acl || [],
    sync_acl: syncAcl,
    auto_reload: autoReload
  };


  try {
    const res = await fetch('/api/config/unbound/structured', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast(data.message, 'success');
      fetchStructuredUnboundConfig();
      if (syncAcl) {
        fetchStructuredDNSDistConfig();
      }
    } else {
      showToast(data.error || 'Gagal menyimpan konfigurasi Unbound.', 'error');
      if (data.details) {
        alert('Detail Kesalahan Sintaks Unbound:\n' + data.details);
      }
    }
  } catch (err) {
    showToast('Gagal menghubungi server: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path>
        <polyline points="17 21 17 13 7 13 7 21"></polyline>
      </svg>
      <span>Simpan &amp; Terapkan Pengaturan Unbound</span>
    `;
  }
}

// Unbound Raw Config
async function fetchUnboundConfig() {
  try {
    const res = await fetch('/api/config/unbound');
    const data = await res.json();
    if (res.ok) {
      const ed = document.getElementById('unbound-editor');
      if (ed) ed.value = data.content;
      const mtimeEl = document.getElementById('unbound-mtime');
      if (mtimeEl) mtimeEl.textContent = 'Terakhir diubah: ' + data.mtime;
    } else {
      showToast('Gagal memuat config unbound: ' + data.error, 'error');
    }
  } catch (err) {
    showToast('Error koneksi saat memuat config unbound', 'error');
  }
}

async function testUnboundSyntax() {
  const content = document.getElementById('unbound-editor').value;
  const banner = document.getElementById('unbound-syntax-banner');
  const btn = document.getElementById('btn-test-unbound');

  btn.disabled = true;
  btn.innerHTML = '<span>Menguji Sintaks...</span>';

  try {
    const res = await fetch('/api/config/unbound/test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content })
    });
    const data = await res.json();

    banner.classList.remove('hidden');
    if (data.valid) {
      banner.className = 'alert-box success mt-3';
      banner.innerHTML = `<strong>Sintaks Unbound Valid!</strong> ${escapeHtml(data.message || 'Konfigurasi smartdns.conf valid dan lolos unbound-checkconf.')}`;
      showToast('Uji sintaks berhasil: Konfigurasi VALID!', 'success');
    } else {
      banner.className = 'alert-box error mt-3';
      banner.innerHTML = `<strong>Sintaks Error Ditemukan:</strong><pre class="font-mono mt-2">${escapeHtml(data.message)}</pre>`;
      showToast('Konfigurasi memiliki kesalahan sintaks.', 'error');
    }
  } catch (err) {
    showToast('Gagal menguji sintaks: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="20 6 9 17 4 12"></polyline>
      </svg>
      <span>Uji Sintaks (Check)</span>
    `;
  }
}

async function saveUnboundRawConfig() {
  const content = document.getElementById('unbound-editor').value;
  const btn = document.getElementById('btn-save-unbound-raw');
  const banner = document.getElementById('unbound-syntax-banner');

  if (!confirm('Simpan perubahan ke /etc/unbound/unbound.conf.d/smartdns.conf?\nCadangan otomatis akan dibuat.')) {
    return;
  }

  btn.disabled = true;
  btn.innerHTML = '<span>Menyimpan...</span>';

  try {
    const res = await fetch('/api/config/unbound/raw', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content, auto_reload: true })
    });
    const data = await res.json();

    if (res.ok && data.success) {
      banner.classList.add('hidden');
      showToast(data.message, 'success');
      fetchUnboundConfig();
    } else {
      banner.classList.remove('hidden');
      banner.className = 'alert-box error mt-3';
      banner.innerHTML = `<strong>Gagal Menyimpan:</strong> ${escapeHtml(data.error)}<pre class="font-mono mt-2">${escapeHtml(data.details || '')}</pre>`;
      showToast('Gagal menyimpan konfigurasi Unbound.', 'error');
    }
  } catch (err) {
    showToast('Koneksi terputus saat menyimpan: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path>
      </svg>
      <span>Simpan Raw Config</span>
    `;
  }
}

async function reloadUnboundService() {
  const btn = document.getElementById('btn-reload-unbound');
  btn.disabled = true;
  btn.innerHTML = '<span>Reloading...</span>';

  try {
    const res = await fetch('/api/config/unbound/reload', { method: 'POST' });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast('Unbound service berhasil direload!', 'success');
    } else {
      showToast('Gagal reload Unbound: ' + (data.details || data.error), 'error');
    }
  } catch (err) {
    showToast('Gagal memanggil API reload: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M23 4v6h-6"></path>
        <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"></path>
      </svg>
      <span>Reload Service</span>
    `;
  }
}

function copyUnboundContent() {
  const ed = document.getElementById('unbound-editor');
  if (ed) {
    copyToClipboard(ed.value, 'Seluruh isi konfigurasi unbound smartdns.conf berhasil disalin!');
  }
}

// --------------------------------------------------------------------------
// Blocklist Sources Editor
// --------------------------------------------------------------------------
async function fetchSourcesConfig() {
  try {
    const res = await fetch('/api/config/sources');
    const data = await res.json();
    if (res.ok) {
      document.getElementById('sources-editor').value = data.content;
      document.getElementById('sources-mtime').textContent = 'Terakhir diubah: ' + data.mtime;

      // Count feeds for overview card
      const lines = data.content.split('\n').filter(l => l.trim() && !l.trim().startsWith('#'));
      document.getElementById('stat-sources-count').textContent = lines.length + ' Feeds';
    }
  } catch (err) {
    showToast('Gagal memuat sumber blocklist', 'error');
  }
}

async function saveSourcesConfig() {
  const content = document.getElementById('sources-editor').value;
  const btn = document.getElementById('btn-save-sources');

  btn.disabled = true;
  btn.innerHTML = '<span>Menyimpan...</span>';

  try {
    const res = await fetch('/api/config/sources', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content })
    });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast(data.message, 'success');
      fetchSourcesConfig();
    } else {
      showToast('Gagal menyimpan sources: ' + data.error, 'error');
    }
  } catch (err) {
    showToast('Error koneksi saat menyimpan sources', 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path>
      </svg>
      <span>Simpan Sumber</span>
    `;
  }
}

async function triggerBlocklistUpdate() {
  if (!confirm('Jalankan skrip pembaruan blocklist sekarang?\nProses akan mengunduh sumber dan mengkompilasi ulang database domains.cdb.')) {
    return;
  }
  try {
    const res = await fetch('/api/blocklist/update', { method: 'POST' });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast('Pembaruan blocklist dimulai di latar belakang!', 'success');
      // Switch to sources tab if not there
      if (currentTab !== 'sources') switchTab('sources');
      pollUpdateLog();
    } else {
      showToast(data.error || 'Gagal memulai pembaruan', 'error');
    }
  } catch (err) {
    showToast('Gagal memicu pembaruan: ' + err.message, 'error');
  }
}

async function fetchUpdateLog() {
  try {
    const res = await fetch('/api/blocklist/update/log?lines=50');
    const data = await res.json();
    const viewer = document.getElementById('log-viewer');
    viewer.textContent = data.log || '(Belum ada catatan log)';
    viewer.scrollTop = viewer.scrollHeight;

    const dot = document.getElementById('log-status-dot');
    if (data.is_running) {
      dot.style.background = '#f59e0b';
      dot.title = 'Sedang berjalan';
    } else {
      dot.style.background = '#10b981';
      dot.title = 'Selesai / Diam';
    }
  } catch (err) {}
}

let pollInterval = null;
function pollUpdateLog() {
  clearInterval(pollInterval);
  let attempts = 0;
  pollInterval = setInterval(async () => {
    await fetchUpdateLog();
    attempts++;
    if (attempts > 30) {
      clearInterval(pollInterval);
      fetchOverviewStats();
    }
  }, 2500);
}

function copySourcesContent() {
  const content = document.getElementById('sources-editor').value;
  copyToClipboard(content, 'Isi sumber blocklist berhasil disalin!');
}

// --------------------------------------------------------------------------
// Active Services Monitor (netstat -ntplu)
// --------------------------------------------------------------------------
async function fetchServices() {
  try {
    const res = await fetch('/api/services');
    const data = await res.json();
    if (res.ok && data.services) {
      allServicesCache = data.services;
      renderServicesTable(allServicesCache);
    }
  } catch (err) {
    console.error('Failed to fetch services:', err);
  }
}

function filterServicesTable() {
  const filter = document.getElementById('service-filter').value.toLowerCase().trim();
  if (!filter) {
    renderServicesTable(allServicesCache);
    return;
  }
  const filtered = allServicesCache.filter(s => {
    return (
      (s.proto && s.proto.toLowerCase().includes(filter)) ||
      (s.local_addr && s.local_addr.toLowerCase().includes(filter)) ||
      (s.port && s.port.toLowerCase().includes(filter)) ||
      (s.state && s.state.toLowerCase().includes(filter)) ||
      (s.pid && s.pid.toLowerCase().includes(filter)) ||
      (s.program && s.program.toLowerCase().includes(filter))
    );
  });
  renderServicesTable(filtered);
}

function renderServicesTable(services) {
  const tbody = document.getElementById('services-tbody');
  if (!services || services.length === 0) {
    tbody.innerHTML = `<tr><td colspan="7" class="text-center py-5 text-muted">Tidak ada servis yang cocok dengan filter.</td></tr>`;
    return;
  }

  tbody.innerHTML = services.map(s => {
    const isTcp = s.proto.startsWith('tcp');
    const protoBadge = isTcp 
      ? `<span class="proto-badge proto-tcp">${s.proto}</span>` 
      : `<span class="proto-badge proto-udp">${s.proto}</span>`;

    const stateBadge = s.state === 'LISTEN' 
      ? `<span class="state-badge state-listen">LISTEN</span>` 
      : `<span class="state-badge state-other">${s.state}</span>`;

    const progDisplay = s.program !== '-' 
      ? `<strong class="text-white">${escapeHtml(s.program)}</strong>` 
      : `<span class="text-muted">-</span>`;

    return `
      <tr>
        <td>${protoBadge}</td>
        <td class="font-mono text-cyan">${escapeHtml(s.local_addr)}</td>
        <td class="port-badge">${escapeHtml(s.port)}</td>
        <td class="font-mono text-muted">${escapeHtml(s.foreign_addr)}</td>
        <td>${stateBadge}</td>
        <td class="font-mono">${escapeHtml(s.pid)}</td>
        <td>${progDisplay}</td>
      </tr>
    `;
  }).join('');
}

function startServicesAutoRefresh() {
  stopServicesAutoRefresh();
  servicesAutoRefreshTimer = setInterval(() => {
    if (currentTab === 'services') {
      fetchServices();
    }
  }, 6000);
}

function stopServicesAutoRefresh() {
  if (servicesAutoRefreshTimer) {
    clearInterval(servicesAutoRefreshTimer);
    servicesAutoRefreshTimer = null;
  }
}

// --------------------------------------------------------------------------
// Utilities
// --------------------------------------------------------------------------
function showToast(message, type = 'success') {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}

function copyToClipboard(text, customMsg) {
  navigator.clipboard.writeText(text).then(() => {
    showToast(customMsg || 'Disalin ke clipboard!', 'success');
  }).catch(() => {
    showToast('Gagal menyalin ke clipboard', 'error');
  });
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function highlightText(text, term) {
  if (!term) return escapeHtml(text);
  const regex = new RegExp(`(${term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi');
  return escapeHtml(text).replace(regex, '<mark style="background:rgba(0,242,254,0.3);color:#fff;border-radius:2px;padding:0 2px;">$1</mark>');
}

function setupKeyboardShortcuts() {
  document.addEventListener('keydown', (e) => {
    // Ctrl+S inside editors
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      if (currentTab === 'dnsdist') {
        e.preventDefault();
        saveDNSDistConfig();
      } else if (currentTab === 'sources') {
        e.preventDefault();
        saveSourcesConfig();
      }
    }
  });
}

// --------------------------------------------------------------------------
// Tools & Maintenance Module
// --------------------------------------------------------------------------
let updateLogPollTimer = null;
let currentUpdateRunning = false;

async function fetchToolsSystemInfo() {
  try {
    const res = await fetch('/api/tools/system-info');
    if (!res.ok) return;
    const data = await res.json();
    
    const ipEl = document.getElementById('machine-ip');
    if (ipEl) {
      const ips = data.server_ips || {};
      const ipv4 = ips.ipv4 || 'IPv4 unavailable';
      const ipv6 = ips.ipv6 || 'IPv6 unavailable';
      ipEl.innerHTML = `<div>IPv4: ${ipv4}</div><div>IPv6: ${ipv6}</div>`;
    }

    const brandVerEl = document.getElementById('brand-version');
    if (brandVerEl) brandVerEl.textContent = data.version ? `v${data.version}` : 'v-';

    const verEl = document.getElementById('tool-smartdns-version');
    if (verEl) verEl.textContent = data.version ? `v${data.version}` : 'v1.0.2';

    const commitEl = document.getElementById('tool-git-commit');
    if (commitEl) commitEl.textContent = `git: ${data.git_branch || 'main'} (${data.git_commit || '-'})`;

    const uuidEl = document.getElementById('tool-uuid');
    if (uuidEl) {
      uuidEl.textContent = data.uuid || '-';
      uuidEl.dataset.fullUuid = data.uuid || '';
    }

    const dnsdistBadge = document.getElementById('tool-dnsdist-badge');
    if (dnsdistBadge) {
      dnsdistBadge.innerHTML = data.dnsdist_active 
        ? '<span class="badge badge-success">ACTIVE</span>'
        : '<span class="badge badge-danger">INACTIVE</span>';
    }

    const unboundBadge = document.getElementById('tool-unbound-badge');
    if (unboundBadge) {
      unboundBadge.innerHTML = data.unbound_active 
        ? '<span class="badge badge-success">ACTIVE</span>'
        : '<span class="badge badge-danger">INACTIVE</span>';
    }
  } catch (err) {
    console.error('Failed to fetch tools system info:', err);
  }
}

function copyUUID() {
  const uuidEl = document.getElementById('tool-uuid');
  const uuid = (uuidEl && uuidEl.dataset.fullUuid) || (uuidEl ? uuidEl.textContent : '');
  if (uuid && uuid !== '-') {
    copyToClipboard(uuid, 'UUID berhasil disalin!');
  }
}

function setDigDomain(domain) {
  const input = document.getElementById('tool-dig-domain');
  if (input) input.value = domain;
}

function setTerminalRunning(cmdDisplay) {
  const statusBadge = document.getElementById('terminal-status-badge');
  const cmdBadge = document.getElementById('terminal-cmd-badge');
  const timeBadge = document.getElementById('terminal-time-badge');
  const output = document.getElementById('tools-terminal-output');

  if (statusBadge) {
    statusBadge.className = 'terminal-status-pill running';
    statusBadge.textContent = 'BERJALAN (RUNNING)';
  }
  if (cmdBadge) cmdBadge.textContent = cmdDisplay || '-';
  if (timeBadge) timeBadge.textContent = '...';
  if (output) {
    output.textContent = `root@SmartDNS:~# ${cmdDisplay}\n[Memproses eksekusi perintah...]`;
  }
}

function setTerminalFinished(success, outputText, cmdDisplay, elapsedMs, exitCode) {
  const statusBadge = document.getElementById('terminal-status-badge');
  const cmdBadge = document.getElementById('terminal-cmd-badge');
  const timeBadge = document.getElementById('terminal-time-badge');
  const output = document.getElementById('tools-terminal-output');

  if (statusBadge) {
    statusBadge.className = `terminal-status-pill ${success ? 'success' : 'error'}`;
    statusBadge.textContent = success ? `SELESAI (CODE ${exitCode !== undefined ? exitCode : 0})` : `GAGAL (CODE ${exitCode || 1})`;
  }
  if (cmdBadge && cmdDisplay) cmdBadge.textContent = cmdDisplay;
  if (timeBadge) timeBadge.textContent = elapsedMs !== undefined ? `${elapsedMs}ms` : '0ms';
  
  if (output) {
    let header = `root@SmartDNS:~# ${cmdDisplay || ''}\n`;
    output.textContent = header + (outputText || '[Output kosong]');
  }

  // Smooth scroll into terminal view
  const section = document.getElementById('tools-terminal-section');
  if (section) {
    section.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }
}

function clearTerminalOutput() {
  const output = document.getElementById('tools-terminal-output');
  const statusBadge = document.getElementById('terminal-status-badge');
  const cmdBadge = document.getElementById('terminal-cmd-badge');
  const timeBadge = document.getElementById('terminal-time-badge');

  if (output) output.textContent = 'Terminal dibersihkan. Siap menerima perintah baru.';
  if (statusBadge) {
    statusBadge.className = 'terminal-status-pill idle';
    statusBadge.textContent = 'SIAP (IDLE)';
  }
  if (cmdBadge) cmdBadge.textContent = '-';
  if (timeBadge) timeBadge.textContent = '0ms';
  showToast('Terminal dibersihkan', 'success');
}

function copyTerminalOutput() {
  const output = document.getElementById('tools-terminal-output');
  if (output) {
    copyToClipboard(output.textContent, 'Isi terminal berhasil disalin!');
  }
}

async function runDigCommand(target) {
  const domainInput = document.getElementById('tool-dig-domain');
  const typeSelect = document.getElementById('tool-dig-type');
  const shortCheck = document.getElementById('tool-dig-short');

  const domain = (domainInput ? domainInput.value.trim() : '') || 'google.com';
  const record_type = typeSelect ? typeSelect.value : 'A';
  const short = shortCheck ? shortCheck.checked : false;

  let cmdLabel = '';
  if (target === 'ipv4') cmdLabel = `dig @127.0.0.1 ${domain} ${record_type}${short ? ' +short' : ''}`;
  else if (target === 'ipv6') cmdLabel = `dig @::1 ${domain} ${record_type}${short ? ' +short' : ''}`;
  else if (target === 'recursive') cmdLabel = `dig @127.0.0.1 -p 5300 ${domain} ${record_type}${short ? ' +short' : ''}`;
  else if (target === 'all') cmdLabel = `dig [Semua Target] ${domain} ${record_type}`;

  setTerminalRunning(cmdLabel);

  const t0 = performance.now();
  try {
    const res = await fetch('/api/tools/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'dig',
        target: target,
        domain: domain,
        record_type: record_type,
        short: short
      })
    });
    const data = await res.json();
    const elapsed = Math.round(performance.now() - t0);

    if (res.ok && data.success) {
      setTerminalFinished(true, data.output, data.command || cmdLabel, data.elapsed_ms || elapsed, data.exit_code);
      showToast(`Uji DNS '${domain}' berhasil!`, 'success');
    } else {
      setTerminalFinished(false, data.output || data.error || 'Terjadi kesalahan eksekusi dig', data.command || cmdLabel, elapsed, data.exit_code || 1);
      showToast(data.error || 'Uji DNS gagal', 'error');
    }
  } catch (err) {
    const elapsed = Math.round(performance.now() - t0);
    setTerminalFinished(false, 'Gagal menghubungi server: ' + err.message, cmdLabel, elapsed, 1);
    showToast('Koneksi gagal: ' + err.message, 'error');
  }
}

async function runConfigCheck(component) {
  let cmdLabel = component === 'unbound' ? 'unbound-checkconf' : (component === 'dnsdist' ? 'dnsdist --check-config' : 'unbound-checkconf && dnsdist --check-config');
  setTerminalRunning(cmdLabel);

  const t0 = performance.now();
  try {
    const res = await fetch('/api/tools/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'checkconf',
        component: component
      })
    });
    const data = await res.json();
    const elapsed = Math.round(performance.now() - t0);

    if (res.ok && data.success) {
      setTerminalFinished(true, data.output, data.command || cmdLabel, elapsed, data.exit_code);
      showToast(`Pengecekan sintaks ${component} valid!`, 'success');
    } else {
      setTerminalFinished(false, data.output || data.error || 'Syntax check mendeteksi masalah', data.command || cmdLabel, elapsed, data.exit_code || 1);
      showToast(`Sintaks ${component} mengandung kesalahan!`, 'error');
    }
  } catch (err) {
    const elapsed = Math.round(performance.now() - t0);
    setTerminalFinished(false, 'Gagal eksekusi: ' + err.message, cmdLabel, elapsed, 1);
    showToast('Koneksi gagal: ' + err.message, 'error');
  }
}

async function runServiceStatus(service) {
  const cmdLabel = `systemctl status ${service}`;
  setTerminalRunning(cmdLabel);

  const t0 = performance.now();
  try {
    const res = await fetch('/api/tools/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'service_status',
        service: service
      })
    });
    const data = await res.json();
    const elapsed = Math.round(performance.now() - t0);

    setTerminalFinished(data.success, data.output, data.command || cmdLabel, elapsed, data.exit_code);
    fetchToolsSystemInfo();
  } catch (err) {
    const elapsed = Math.round(performance.now() - t0);
    setTerminalFinished(false, 'Gagal eksekusi: ' + err.message, cmdLabel, elapsed, 1);
  }
}

async function runServiceRestart(service) {
  const cmdLabel = service === 'both' ? 'systemctl restart unbound && systemctl restart dnsdist' : `systemctl restart ${service}`;
  setTerminalRunning(cmdLabel);

  const t0 = performance.now();
  try {
    const res = await fetch('/api/tools/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'service_restart',
        service: service
      })
    });
    const data = await res.json();
    const elapsed = Math.round(performance.now() - t0);

    if (data.success) {
      setTerminalFinished(true, data.output, data.command || cmdLabel, elapsed, data.exit_code);
      showToast(`Service ${service} berhasil di-restart!`, 'success');
    } else {
      setTerminalFinished(false, data.output || data.error, data.command || cmdLabel, elapsed, data.exit_code || 1);
      showToast(`Restart service ${service} gagal`, 'error');
    }
    fetchToolsSystemInfo();
    fetchOverviewStats();
  } catch (err) {
    const elapsed = Math.round(performance.now() - t0);
    setTerminalFinished(false, 'Gagal restart service: ' + err.message, cmdLabel, elapsed, 1);
    showToast('Koneksi gagal', 'error');
  }
}

async function runHeartbeat() {
  const cmdLabel = '/usr/local/bin/smartdns-heartbeat';
  setTerminalRunning(cmdLabel);

  const t0 = performance.now();
  try {
    const res = await fetch('/api/tools/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'heartbeat' })
    });
    const data = await res.json();
    const elapsed = Math.round(performance.now() - t0);

    if (data.success) {
      setTerminalFinished(true, data.output, data.command || cmdLabel, elapsed, data.exit_code);
      showToast('Heartbeat telemetri berhasil terkirim!', 'success');
      fetchToolsSystemInfo();
    } else {
      setTerminalFinished(false, data.output || data.error, data.command || cmdLabel, elapsed, data.exit_code || 1);
      showToast('Pengiriman heartbeat gagal', 'error');
    }
  } catch (err) {
    const elapsed = Math.round(performance.now() - t0);
    setTerminalFinished(false, 'Gagal: ' + err.message, cmdLabel, elapsed, 1);
    showToast('Koneksi gagal', 'error');
  }
}

async function runViewMetadata() {
  const cmdLabel = 'cat /var/lib/smartdns/install.json';
  setTerminalRunning(cmdLabel);

  const t0 = performance.now();
  try {
    const res = await fetch('/api/tools/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'metadata' })
    });
    const data = await res.json();
    const elapsed = Math.round(performance.now() - t0);
    setTerminalFinished(data.success, data.output, data.command || cmdLabel, elapsed, data.exit_code);
  } catch (err) {
    setTerminalFinished(false, err.message, cmdLabel, 0, 1);
  }
}

async function runViewInstallEnv() {
  const cmdLabel = 'cat /var/lib/smartdns/install.env';
  setTerminalRunning(cmdLabel);

  const t0 = performance.now();
  try {
    const res = await fetch('/api/tools/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'install_env' })
    });
    const data = await res.json();
    const elapsed = Math.round(performance.now() - t0);
    setTerminalFinished(data.success, data.output, data.command || cmdLabel, elapsed, data.exit_code);
  } catch (err) {
    setTerminalFinished(false, err.message, cmdLabel, 0, 1);
  }
}

async function runQuickDiagnostics() {
  const btn = document.getElementById('btn-quick-diag');
  if (btn) btn.disabled = true;

  setTerminalRunning('Quick Health Check (Unbound Checkconf + DNSDist Check-Config + Live Dig IPv4)');

  const t0 = performance.now();
  try {
    const [c1, c2, d1] = await Promise.all([
      fetch('/api/tools/exec', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'checkconf', component: 'unbound' }) }).then(r => r.json()),
      fetch('/api/tools/exec', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'checkconf', component: 'dnsdist' }) }).then(r => r.json()),
      fetch('/api/tools/exec', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'dig', target: 'ipv4', domain: 'google.com', record_type: 'A', short: true }) }).then(r => r.json())
    ]);

    const elapsed = Math.round(performance.now() - t0);
    const allOk = c1.success && c2.success && d1.success;

    let out = `===========================================================\n`;
    out += `  HASIL QUICK HEALTH CHECK SISTEM SMARTDNS\n`;
    out += `===========================================================\n\n`;
    out += `[1/3] UNBOUND CONFIG CHECK:\nStatus: ${c1.success ? 'PASSED [OK]' : 'FAILED [ERROR]'}\n${c1.output}\n\n`;
    out += `[2/3] DNSDIST CONFIG CHECK:\nStatus: ${c2.success ? 'PASSED [OK]' : 'FAILED [ERROR]'}\n${c2.output}\n\n`;
    out += `[3/3] LIVE DNS RESOLUTION (google.com @ 127.0.0.1:53):\nStatus: ${d1.success ? 'PASSED [OK]' : 'FAILED [ERROR]'}\nHasil IP: ${d1.output}\n\n`;
    out += `KESIMPULAN: ${allOk ? 'SELURUH SISTEM DNS BERJALAN NORMAL DENGAN BAIK!' : 'PERHATIAN: Ada komponen konfigurasi yang memerlukan inspeksi.'}`;

    setTerminalFinished(allOk, out, 'Quick Health Check Diagnostic Suite', elapsed, allOk ? 0 : 1);
    showToast(allOk ? 'Health check sempurna! Seluruh komponen normal.' : 'Health check mendeteksi masalah!', allOk ? 'success' : 'warning');
    fetchToolsSystemInfo();
  } catch (err) {
    setTerminalFinished(false, 'Gagal menjalankan health check: ' + err.message, 'Quick Health Check', 0, 1);
  } finally {
    if (btn) btn.disabled = false;
  }
}

// --------------------------------------------------------------------------
// Update & Patching Logic
// --------------------------------------------------------------------------
async function triggerUpdate(updateType) {
  if (currentUpdateRunning) {
    showToast('Proses update saat ini masih berjalan.', 'warning');
    return;
  }

  const cmdNames = {
    patch: 'cd SmartDNS && bash update.sh --patch'
  };

  const cmdDisplay = cmdNames[updateType] || `Update (${updateType})`;
  setTerminalRunning(cmdDisplay);

  try {
    const res = await fetch('/api/tools/update', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: updateType })
    });
    const data = await res.json();

    if (res.ok && data.success) {
      showToast(`Proses update '${updateType}' berhasil dimulai.`, 'success');
      currentUpdateRunning = true;
      startUpdateLogPolling(cmdDisplay);
    } else {
      setTerminalFinished(false, data.error || 'Gagal memulai pembaruan', cmdDisplay, 0, 1);
      showToast(data.error || 'Gagal memulai update', 'error');
    }
  } catch (err) {
    setTerminalFinished(false, 'Koneksi error: ' + err.message, cmdDisplay, 0, 1);
    showToast('Gagal terhubung ke server', 'error');
  }
}

function startUpdateLogPolling(cmdDisplay) {
  if (updateLogPollTimer) clearInterval(updateLogPollTimer);

  updateLogPollTimer = setInterval(async () => {
    try {
      const res = await fetch('/api/tools/update/log?lines=150');
      if (!res.ok) return;
      const data = await res.json();

      const outputEl = document.getElementById('tools-terminal-output');
      if (outputEl) {
        outputEl.textContent = `root@SmartDNS:~# ${cmdDisplay}\n\n` + (data.log || '[Menunggu output log...]');
        outputEl.scrollTop = outputEl.scrollHeight;
      }

      if (!data.is_running && data.status !== 'running') {
        clearInterval(updateLogPollTimer);
        updateLogPollTimer = null;
        currentUpdateRunning = false;

        const isSuccess = data.status === 'finished';
        setTerminalFinished(isSuccess, (data.log || '') + `\n\n[Status Selesai: ${data.status.toUpperCase()}]`, cmdDisplay, 0, isSuccess ? 0 : 1);
        showToast(isSuccess ? 'Pembaruan sistem berhasil diselesaikan!' : 'Proses pembaruan selesai dengan catatan/peringatan.', isSuccess ? 'success' : 'warning');
        fetchToolsSystemInfo();
        fetchOverviewStats();
      }
    } catch (err) {
      console.error('Error polling update log:', err);
    }
  }, 1200);
}

