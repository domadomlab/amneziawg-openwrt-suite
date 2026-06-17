module("luci.controller.shuka_hybrid", package.seeall)

function index()
    entry({"admin", "services"}, firstchild(), _("Services"), 40).index = true
    entry({"admin", "services", "shuka"}, call("action_gui"), "Shuka VPN", 60)
    entry({"admin", "services", "shuka", "sync"}, call("action_sync"), nil).leaf = true
    entry({"admin", "services", "shuka", "data"}, call("action_data"), nil).leaf = true
    entry({"admin", "services", "shuka", "select"}, call("action_select"), nil).leaf = true
    entry({"admin", "services", "shuka", "start"}, call("action_start"), nil).leaf = true
    entry({"admin", "services", "shuka", "stop"}, call("action_stop"), nil).leaf = true
    entry({"admin", "services", "shuka", "amnezia_upload"}, call("action_amnezia_upload"), nil).leaf = true
end

local function strip(s)
    if not s then return "" end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

function action_sync()
    local url = luci.http.formvalue("url")
    if url then
        local f = io.open("/etc/sing-box/sub_url.txt", "w")
        f:write(url)
        f:close()
    end
    os.execute("/usr/bin/shuka_manager.py sync >/dev/null 2>&1 &")
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_amnezia_upload()
    local http = require "luci.http"
    local tmp = "/tmp/amnezia_upload.conf"
    local fp = io.open(tmp, "w")
    http.setfilehandler(function(m, c, e)
        if c then fp:write(c) end
        if e then fp:close() end
    end)
    http.formvalue("amneziadata")
    
    os.execute("/usr/bin/shuka_manager.py amnezia " .. tmp .. " >/dev/null 2>&1 &")
    http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end

function action_delete_amnezia()
    local tag = luci.http.formvalue("tag")
    if tag then
        os.execute("/usr/bin/shuka_manager.py del_amnezia " .. luci.util.shellquote(tag) .. " >/dev/null 2>&1 &")
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_select()
    local tag = luci.http.formvalue("tag")
    if tag then
        os.execute("/usr/bin/shuka_manager.py select " .. luci.util.shellquote(tag) .. " >/dev/null 2>&1 &")
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_data()
    local util = require "luci.util"
    local http = require "luci.http"
    local json = require "luci.jsonc"
    local fs = require "nixio.fs"
    
    local rx = "0"
    local tx = "0"
    local interface_up = false
    
    -- Check Sing-box stats
    local tun_rx = util.exec("cat /sys/class/net/tun-shuka/statistics/rx_bytes 2>/dev/null")
    local tun_tx = util.exec("cat /sys/class/net/tun-shuka/statistics/tx_bytes 2>/dev/null")
    
    -- Check Amnezia kernel stats
    local awg_rx = util.exec("cat /sys/class/net/awg0/statistics/rx_bytes 2>/dev/null")
    local awg_tx = util.exec("cat /sys/class/net/awg0/statistics/tx_bytes 2>/dev/null")
    
    if tun_rx ~= "" and tun_rx ~= "0" then
        rx = tun_rx
        tx = tun_tx
        interface_up = (util.exec("ip addr show tun-shuka 2>/dev/null | grep 'inet '") ~= "")
    elseif awg_rx ~= "" then
        rx = awg_rx
        tx = awg_tx
        interface_up = (util.exec("ip addr show awg0 2>/dev/null | grep 'inet '") ~= "")
    end
    
    local ip = util.exec("curl -s --connect-timeout 2 ifconfig.me")
    if ip == "" then ip = "Offline" end
    
    local servers = {}
    local active_tag = ""
    
    -- 1. Get Shuka servers from config.json
    local config_raw = util.exec("cat /etc/sing-box/config.json 2>/dev/null")
    if config_raw ~= "" then
        local config = json.parse(config_raw)
        if config and config.outbounds then
            for _, ob in ipairs(config.outbounds) do
                if ob.type == "vless" or ob.type == "shadowsocks" or ob.type == "wireguard" then
                    table.insert(servers, {tag = ob.tag, type = ob.type, server = ob.server})
                end
            end
            if config.route and config.route.rules then
                for _, rule in ipairs(config.route.rules) do
                    if rule.outbound and rule.outbound ~= "direct" and rule.outbound ~= "block" and rule.outbound ~= "dns-out" then
                        active_tag = rule.outbound
                    end
                end
            end
        end
    end
    
    -- 2. Get Amnezia servers from persistent storage
    local am_storage = "/etc/sing-box/amnezia_profiles.json"
    local am_raw = util.exec("cat " .. am_storage .. " 2>/dev/null")
    if am_raw ~= "" then
        local am_profiles = json.parse(am_raw)
        if am_profiles then
            for _, p in ipairs(am_profiles) do
                table.insert(servers, p)
            end
        end
    end

    -- 3. Determine if Amnezia is ACTIVE
    local handshake = tonumber(util.exec("awg-new show awg0 latest-handshakes 2>/dev/null | awk '{print $NF}'") or "0") or 0
    if handshake > 0 then
        -- Find which amnezia profile is active by checking awg0 show
        local pubkey = util.exec("awg-new show awg0 public-key 2>/dev/null"):gsub("%s+", "")
        -- We could match by pubkey but for now let's just mark it if active
        active_tag = "Amnezia-Profile" -- Default fallback or logic to match
    end
    
    local is_running = (util.exec("pgrep sing-box") ~= "") or (handshake > 0)
    
    local data = {
        rx = strip(rx),
        tx = strip(tx),
        ip = strip(ip),
        servers = servers,
        active_tag = active_tag,
        is_running = is_running,
        interface_up = interface_up
    }
    
    http.prepare_content("application/json")
    http.write_json(data)
end

function action_gui()
    local fs = require "nixio.fs"
    local util = require "luci.util"
    local sub_url = fs.access("/etc/sing-box/sub_url.txt") and util.exec("cat /etc/sing-box/sub_url.txt") or ""

    luci.http.prepare_content("text/html")
    luci.http.write([[
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Shuka Hybrid Panel</title>
    <style>
        :root {
            --bg-dark: #0f172a; --card-bg: #1e293b; --accent: #6f42c1;
            --shuka-accent: #38bdf8; --text-main: #f1f5f9; --text-dim: #94a3b8;
            --success: #22c55e; --danger: #ef4444; --warning: #f59e0b;
        }
        body { font-family: sans-serif; background: var(--bg-dark); color: var(--text-main); margin: 0; padding: 10px; overflow-x: hidden; }
        .card { background: var(--card-bg); padding: 20px; border-radius: 16px; max-width: 900px; margin: 10px auto; box-shadow: 0 10px 25px rgba(0,0,0,0.5); border: 1px solid rgba(255,255,255,0.05); box-sizing: border-box; width: 100%; }
        .header { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; margin-bottom: 20px; }
        .stats-grid { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 20px; }
        .stat-card { flex: 1; min-width: 140px; background: rgba(0,0,0,0.2); padding: 12px; border-radius: 12px; text-align: center; border: 1px solid rgba(255,255,255,0.05); }
        .stat-val { font-size: 16px; font-weight: bold; display: block; color: var(--shuka-accent); text-overflow: ellipsis; overflow: hidden; }
        .stat-label { font-size: 10px; color: var(--text-dim); text-transform: uppercase; margin-top: 4px; display: block; }
        .main-layout { display: flex; flex-direction: column; gap: 20px; }
        @media (min-width: 768px) { .main-layout { flex-direction: row; } .main-layout > div { flex: 1; } }
        .btn { padding: 10px 16px; border-radius: 8px; border: none; cursor: pointer; font-weight: bold; transition: 0.2s; text-align: center; display: inline-block; font-size: 14px; text-decoration: none; }
        .btn-primary { background: var(--shuka-accent); color: var(--bg-dark); }
        .btn-stop { background: var(--danger); color: white; }
        .btn-sync { background: var(--accent); color: white; width: 100%; margin-top: 10px; }
        .btn-amnezia { background: #6f42c1; color: white; margin-top: 10px; width: 100%; }
        .server-list { max-height: 400px; overflow-y: auto; background: rgba(0,0,0,0.2); border-radius: 12px; padding: 10px; border: 1px solid rgba(255,255,255,0.05); }
        .server-item { background: rgba(255,255,255,0.05); padding: 12px; border-radius: 8px; margin-bottom: 8px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; border: 1px solid transparent; transition: 0.2s; }
        .server-item:hover { background: rgba(255,255,255,0.1); border-color: var(--shuka-accent); }
        .server-item.active { border-color: var(--shuka-accent); background: rgba(56, 189, 248, 0.15); }
        .active-dot { width: 8px; height: 8px; background: var(--success); border-radius: 50%; display: inline-block; margin-right: 8px; box-shadow: 0 0 8px var(--success); }
        input[type="text"] { width: 100%; background: rgba(0,0,0,0.3); color: #fff; border: 1px solid rgba(255,255,255,0.1); padding: 12px; border-radius: 8px; box-sizing: border-box; font-size: 14px; }
        pre { background: #000; color: #0f0; padding: 10px; border-radius: 8px; font-size: 11px; height: 120px; overflow-x: auto; white-space: pre-wrap; word-wrap: break-word; border: 1px solid #333; margin-top: 10px; width: 100%; box-sizing: border-box; }
        .section-title { font-size: 16px; color: var(--shuka-accent); margin-top: 0; border-left: 3px solid var(--shuka-accent); padding-left: 10px; }
    </style>
    <script>
        function formatBytes(bytes) {
            if (bytes == 0) return "0.00 MB";
            let val = bytes / 1024 / 1024;
            if (val > 1024) return (val / 1024).toFixed(2) + " GB";
            return val.toFixed(2) + " MB";
        }
        function updateData() {
            fetch('shuka/data')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('rx-val').textContent = formatBytes(data.rx);
                    document.getElementById('tx-val').textContent = formatBytes(data.tx);
                    document.getElementById('ip-badge').textContent = data.ip;
                    
                    const statusLabel = document.getElementById('status-label');
                    if (data.interface_up) {
                        statusLabel.textContent = 'В СЕТИ';
                        statusLabel.style.color = 'var(--success)';
                    } else if (data.is_running) {
                        statusLabel.textContent = 'ЗАПУСК...';
                        statusLabel.style.color = 'var(--warning)';
                    } else {
                        statusLabel.textContent = 'ОСТАНОВЛЕН';
                        statusLabel.style.color = 'var(--danger)';
                    }
                    
                    const syncInfo = document.getElementById('sync-info');
                    if (syncInfo) syncInfo.textContent = 'Обновлено: ' + (data.last_sync || 'Никогда');
                    
                    const list = document.getElementById('server-list');
                    list.innerHTML = '';
                    if (!data.servers || data.servers.length === 0) {
                        list.innerHTML = '<div style="color:var(--text-dim); text-align:center; padding:20px;">Список пуст. Добавьте серверы.</div>';
                    } else {
                        data.servers.forEach(s => {
                            const div = document.createElement('div');
                            // Active tag logic
                            const isActive = (s.tag === data.active_tag) || (s.type === 'amneziawg' && data.active_tag === 'Amnezia-Profile');
                            div.className = 'server-item' + (isActive ? ' active' : '');
                            div.onclick = () => selectServer(s.tag);
                            
                            let delBtn = '';
                            if (s.type === 'amneziawg') {
                                delBtn = `<button class="btn-del-mini" onclick="event.stopPropagation(); deleteAmnezia('${s.tag}')">✕</button>`;
                            }

                            div.innerHTML = '<div style="display:flex; align-items:center;">' + (isActive ? '<span class="active-dot"></span>' : '') + 
                                           '<strong>' + s.tag + '</strong></div>' +
                                           '<div style="display:flex; align-items:center;"><span style="font-size:10px; color:var(--text-dim)">' + s.type.toUpperCase() + '</span>' + delBtn + '</div>';
                            list.appendChild(div);
                        });
                    }
                    const logOutput = document.getElementById('log-output');
                    if (data.health_log) {
                        logOutput.textContent = "--- Health Log ---\n" + data.health_log;
                    }
                })
                .catch(e => console.error("Data error:", e));
        }
        function sync() {
            const url = document.getElementById('sub-url').value;
            if (!url) return;
            fetch('shuka/sync?url=' + encodeURIComponent(url)).then(() => {
                alert('Обновление подписки...');
                setTimeout(updateData, 3000);
            });
        }
        function selectServer(tag) {
            fetch('shuka/select?tag=' + encodeURIComponent(tag)).then(() => {
                setTimeout(updateData, 1000);
            });
        }
        function deleteAmnezia(tag) {
            if (confirm('Удалить профиль ' + tag + '?')) {
                fetch('shuka/delete_amnezia?tag=' + encodeURIComponent(tag)).then(() => {
                    setTimeout(updateData, 1000);
                });
            }
        }
        window.onload = () => { setInterval(updateData, 5000); updateData(); };
    </script>
</head>
<body>
    <div class="card">
        <div class="header">
            <div style="display:flex; align-items:center; gap:10px;">
                <h2 style="margin:0;">🚀 Shuka Hybrid</h2>
                <span style="font-size:10px; color:var(--shuka-accent); border:1px solid; padding:2px 6px; border-radius:4px;">v4.0.2 LTS</span>
            </div>
            <div style="display:flex; gap: 8px;">
                <a href="shuka/start" class="btn btn-primary">СТАРТ</a>
                <a href="shuka/stop" class="btn btn-stop">СТОП</a>
            </div>
        </div>

        <div class="stats-grid">
            <div class="stat-card"><span id="rx-val" class="stat-val">0.00 MB</span><span class="stat-label">Входящий</span></div>
            <div class="stat-card"><span id="tx-val" class="stat-val">0.00 MB</span><span class="stat-label">Исходящий</span></div>
            <div id="active-server-card" class="stat-card"><span id="active-server-label" class="stat-val">---</span><span class="stat-label">Активный сервер</span></div>
            <div class="stat-card"><span id="ip-badge" class="stat-val">---</span><span class="stat-label">Внешний IP</span></div>
            <div class="stat-card"><span id="status-label" class="stat-val" style="color:var(--danger)">---</span><span class="stat-label">Статус</span></div>
        </div>

        <div class="main-layout">
            <div>
                <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(0,0,0,0.2); padding:10px; border-radius:8px; margin-bottom:15px; border:1px solid rgba(255,255,255,0.05);">
                    <div style="display:flex; flex-direction:column;">
                        <h3 class="section-title" style="margin:0;">🔗 Подписка Shuka</h3>
                        <span id="sync-info" style="font-size:10px; color:var(--text-dim); margin-top:4px;">📅 Обновлено: ---</span>
                    </div>
                    <button class="btn btn-primary" style="padding:6px 12px; font-size:11px;" onclick="sync()">ОБНОВИТЬ</button>
                </div>
                <input type="text" id="sub-url" placeholder="VLESS / Shadowsocks URL..." value="]]..sub_url..[[">

                <h3 class="section-title" style="margin-top:25px;">📋 Журнал событий</h3>
                <pre id="log-output" style="height:200px;">]] .. util.exec("logread | grep -Ei 'sing-box|amnezia' | tail -n 20") .. [[</pre>
                
                <h3 class="section-title" style="margin-top:25px;">✨ AmneziaWG Профиль</h3>
                <form method="post" action="amnezia_upload" enctype="multipart/form-data">
                    <input type="file" name="amneziadata" id="amneziadata" style="display:none;" onchange="this.form.submit()">
                    <button type="button" class="btn btn-amnezia" onclick="document.getElementById('amneziadata').click()">📁 ИМПОРТ .CONF</button>
                </form>
                
                <h3 class="section-title" style="margin-top:25px;">📋 Логи</h3>
                <pre id="log-output">]] .. util.exec("logread | grep -Ei 'sing-box|amnezia' | tail -n 10") .. [[</pre>
            </div>
            <div>
                <h3 class="section-title">🌍 Выбор Сервера</h3>
                <div id="server-list" class="server-list">Загрузка...</div>
            </div>
        </div>
    </div>
</body>
</html>
]])
end

function action_start()
    os.execute("/usr/bin/shuka_manager.py start >/dev/null 2>&1 &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end

function action_stop()
    os.execute("/usr/bin/shuka_manager.py stop >/dev/null 2>&1 &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end
atcher.build_url("admin", "services", "shuka"))
end
d

function action_stop()
    os.execute("/usr/bin/shuka_manager.py stop >/dev/null 2>&1 &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end
