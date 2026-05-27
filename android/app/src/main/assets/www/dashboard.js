var MONITOR_PORT = 5001;
var POLL_INTERVAL = 3000;
var LOG_INTERVAL = 2000;
var pollTimer = null;
var logTimer = null;

function api(path, method, body, cb) {
  var xhr = new XMLHttpRequest();
  xhr.open(method || 'GET', 'http://127.0.0.1:' + MONITOR_PORT + path, true);
  xhr.setRequestHeader('Content-Type', 'application/json');
  xhr.onreadystatechange = function() {
    if (xhr.readyState === 4) {
      if (xhr.status >= 200 && xhr.status < 300) {
        try { cb(null, JSON.parse(xhr.responseText)); }
        catch(e) { cb(null, null); }
      } else {
        cb(new Error('HTTP ' + xhr.status));
      }
    }
  };
  xhr.onerror = function() { cb(new Error('Network error')); };
  xhr.send(body || null);
}

function fmtUptime(sec) {
  if (!sec || sec < 0) return '-';
  var h = Math.floor(sec / 3600);
  var m = Math.floor((sec % 3600) / 60);
  var s = Math.floor(sec % 60);
  return (h > 0 ? h + 'h ' : '') + m + 'm ' + s + 's';
}

function fmtMemory(kb) {
  if (!kb) return '-';
  var mb = kb / 1024;
  if (mb < 1024) return mb.toFixed(0) + ' MB';
  return (mb / 1024).toFixed(1) + ' GB';
}

function showMsg(text) {
  var el = document.getElementById('statusBadge');
  el.textContent = text;
  el.className = 'badge warn';
}

function updateStatus(data) {
  var badge = document.getElementById('statusBadge');
  badge.textContent = data.status || 'unknown';
  badge.className = 'badge ' + (data.status || 'stopped');

  document.getElementById('pid').textContent = data.pid > 0 ? data.pid : '-';
  document.getElementById('uptime').textContent = fmtUptime(data.uptime_sec);
  document.getElementById('memory').textContent = fmtMemory(data.memory_kb);
  document.getElementById('restartCount').textContent = data.restart_count || 0;

  // Health check
  var healthRow = document.getElementById('healthRow');
  if (data.status === 'healthy') {
    healthRow.style.display = 'flex';
    document.getElementById('healthDot').className = 'dot ok';
    document.getElementById('healthText').textContent = 'OSRM API 正常回應';
  } else if (data.status === 'running') {
    healthRow.style.display = 'flex';
    document.getElementById('healthDot').className = 'dot unknown';
    document.getElementById('healthText').textContent = 'OSRM API 尚未回應';
  } else {
    healthRow.style.display = 'none';
  }

  // Config sync
  if (data.config) {
    if (data.config.monitor_port) MONITOR_PORT = data.config.monitor_port;
    document.getElementById('cfgIp').value = data.config.ip || '127.0.0.1';
    document.getElementById('cfgPort').value = data.config.port || 5747;
    document.getElementById('cfgDataDir').value = data.config.data_dir || '';
    document.getElementById('cfgAutoStart').checked = data.config.auto_start !== false;
    document.getElementById('cfgAutoRestart').checked = data.config.auto_restart !== false;
  }

  // Buttons
  var isRunning = (data.status === 'running' || data.status === 'healthy');
  document.getElementById('btnStart').disabled = isRunning;
  document.getElementById('btnStop').disabled = !isRunning;
  document.getElementById('btnRestart').disabled = !isRunning;
}

function updateLogs(data) {
  if (!data || !data.lines || !data.lines.length) return;
  var pre = document.getElementById('logBody');
  var autoScroll = (pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 10);
  for (var i = 0; i < data.lines.length; i++) {
    var line = data.lines[i].m || '';
    pre.textContent += line + '\n';
  }
  if (pre.textContent.length > 50000) {
    pre.textContent = pre.textContent.slice(-30000);
  }
  if (autoScroll) pre.scrollTop = pre.scrollHeight;
  pre.scrollTop = pre.scrollHeight;
}

function pollStatus() {
  api('/status', 'GET', null, function(err, data) {
    if (err) {
      document.getElementById('statusBadge').textContent = 'disconnected';
      document.getElementById('statusBadge').className = 'badge crashed';
    } else {
      updateStatus(data);
      maybeAutoStart(data);
    }
  });
}

function pollLogs() {
  var pre = document.getElementById('logBody');
  var lineCount = pre.textContent.split('\n').length - 1;
  api('/logs?n=' + (lineCount > 200 ? 50 : 100), 'GET', null, function(err, data) {
    if (!err) updateLogs(data);
  });
}

function doStart() {
  api('/start', 'POST', null, function(err, data) {
    if (err) showMsg('啟動失敗: ' + err.message);
    else setTimeout(pollStatus, 500);
  });
}

function doStop() {
  api('/stop', 'POST', null, function(err, data) {
    if (err) showMsg('停止失敗: ' + err.message);
    else setTimeout(pollStatus, 1000);
  });
}

function doRestart() {
  api('/restart', 'POST', null, function(err, data) {
    if (err) showMsg('重啟失敗: ' + err.message);
    else setTimeout(pollStatus, 1500);
  });
}

function toggleConfig() {
  var body = document.getElementById('configBody');
  body.style.display = body.style.display === 'none' ? 'block' : 'none';
  document.getElementById('toggleConfigBtn').textContent =
    body.style.display === 'none' ? '展開' : '收合';
  if (body.style.display === 'block') loadConfig();
}

function loadConfig() {
  api('/config', 'GET', null, function(err, data) {
    if (data) {
      document.getElementById('cfgIp').value = data.ip || '127.0.0.1';
      document.getElementById('cfgPort').value = data.port || 5747;
      document.getElementById('cfgDataDir').value = data.data_dir || '';
      document.getElementById('cfgAutoStart').checked = data.auto_start !== false;
      document.getElementById('cfgAutoRestart').checked = data.auto_restart !== false;
    }
  });
}

function saveConfig() {
  var body = JSON.stringify({
    ip: document.getElementById('cfgIp').value,
    port: parseInt(document.getElementById('cfgPort').value) || 5747,
    data_dir: document.getElementById('cfgDataDir').value,
    auto_start: document.getElementById('cfgAutoStart').checked,
    auto_restart: document.getElementById('cfgAutoRestart').checked
  });
  api('/config', 'POST', body, function(err, data) {
    var msg = document.getElementById('configMsg');
    if (err) {
      msg.textContent = '儲存失敗: ' + err.message;
      msg.style.color = 'var(--red)';
    } else {
      msg.textContent = '已儲存，引擎重啟中…';
      msg.style.color = 'var(--green)';
      setTimeout(function() { msg.textContent = ''; }, 3000);
      setTimeout(pollStatus, 2000);
    }
  });
}

function init() {
  pollStatus();
  pollTimer = setInterval(pollStatus, POLL_INTERVAL);
  setTimeout(function() {
    pollLogs();
    logTimer = setInterval(pollLogs, LOG_INTERVAL);
  }, 500);
}

// 首次載入時若引擎已設定 auto-start 則自動啟動
var autoStartOnce = true;
function maybeAutoStart(data) {
  if (autoStartOnce && data.status === 'stopped' && data.config && data.config.auto_start) {
    autoStartOnce = false;
    setTimeout(doStart, 1000);
  }
}
window.onload = init;
