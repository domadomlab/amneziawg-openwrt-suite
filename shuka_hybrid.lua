module("luci.controller.shuka_hybrid", package.seeall)

function index()
    entry({"admin", "services", "shuka"}, call("action_gui"), _("Shuka VPN"), 60)
    entry({"admin", "services", "shuka", "sync"}, call("action_sync"), nil).leaf = true
    entry({"admin", "services", "shuka", "data"}, call("action_data"), nil).leaf = true
    entry({"admin", "services", "shuka", "select"}, call("action_select"), nil).leaf = true
    entry({"admin", "services", "shuka", "start"}, call("action_start"), nil).leaf = true
    entry({"admin", "services", "shuka", "stop"}, call("action_stop"), nil).leaf = true
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
    -- Reset to template to avoid duplicate tags or broken rules
    os.execute("cp /etc/sing-box/config.json.template /etc/sing-box/config.json")
    os.execute("/usr/bin/shuka_manager.py sync &")
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_select()
    local tag = luci.http.formvalue("tag")
    if tag then
        os.execute("/usr/bin/shuka_manager.py select " .. luci.util.shellquote(tag) .. " &")
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_data()
    local util = require "luci.util"
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    local rx = util.exec("cat /sys/class/net/tun-shuka/statistics/rx_bytes 2>/dev/null") or "0"
    local tx = util.exec("cat /sys/class/net/tun-shuka/statistics/tx_bytes 2>/dev/null") or "0"
    
    local ip = util.exec("curl -s --connect-timeout 2 ifconfig.me")
    if ip == "" then ip = "Offline" end
    
    local servers = {}
    local active_tag = ""
    local config_raw = util.exec("cat /etc/sing-box/config.json 2>/dev/null")
    if config_raw ~= "" then
        local config = json.parse(config_raw)
        if config then
            if config.outbounds then
                for _, ob in ipairs(config.outbounds) do
                    if ob.type == "vless" or ob.type == "shadowsocks" or ob.type == "wireguard" or ob.type == "amneziawg" then
                        table.insert(servers, {tag = ob.tag, type = ob.type, server = ob.server})
                    end
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
    
    -- Using more lenient pgrep
    local is_running = (util.exec("pgrep sing-box") ~= "")
    local interface_up = (util.exec("ip addr show tun-shuka 2>/dev/null | grep 'inet '") ~= "")
    
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
    <title>Shuka VLESS/Reality Panel</title>
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
        .server-list { max-height: 400px; overflow-y: auto; background: rgba(0,0,0,0.2); border-radius: 12px; padding: 10px; border: 1px solid rgba(255,255,255,0.05); }
        .server-item { background: rgba(255,255,255,0.05); padding: 12px; border-radius: 8px; margin-bottom: 8px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; border: 1px solid transparent; transition: 0.2s; }
        .server-item:hover { background: rgba(255,255,255,0.1); border-color: var(--shuka-accent); }
        .server-item.active { border-color: var(--shuka-accent); background: rgba(56, 189, 248, 0.15); }
        .active-dot { width: 8px; height: 8px; background: var(--success); border-radius: 50%; display: inline-block; margin-right: 8px; box-shadow: 0 0 8px var(--success); }
        input[type="text"] { width: 100%; background: rgba(0,0,0,0.3); color: #fff; border: 1px solid rgba(255,255,255,0.1); padding: 12px; border-radius: 8px; box-sizing: border-box; font-size: 14px; }
        pre { background: #000; color: #0f0; padding: 10px; border-radius: 8px; font-size: 11px; height: 120px; overflow-x: auto; white-space: pre-wrap; word-wrap: break-word; border: 1px solid #333; margin-top: 10px; width: 100%; box-sizing: border-box; }
    </style>
    <script>
        function updateData() {
            fetch('shuka/data')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('rx-val').textContent = (data.rx / 1024 / 1024).toFixed(2) + " MB";
                    document.getElementById('tx-val').textContent = (data.tx / 1024 / 1024).toFixed(2) + " MB";
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
                    
                    const list = document.getElementById('server-list');
                    list.innerHTML = '';
                    if (!data.servers || data.servers.length === 0) {
                        list.innerHTML = '<div style="color:var(--text-dim); text-align:center; padding:20px;">Список пуст. Обновите подписку.</div>';
                    } else {
                        data.servers.forEach(s => {
                            const div = document.createElement('div');
                            const isActive = (s.tag === data.active_tag);
                            div.className = 'server-item' + (isActive ? ' active' : '');
                            div.onclick = () => selectServer(s.tag);
                            div.innerHTML = '<span>' + (isActive ? '<span class="active-dot"></span>' : '') + 
                                           '<strong>' + s.tag + '</strong></span>' +
                                           '<span style="font-size:10px; color:var(--text-dim)">' + s.type.toUpperCase() + '</span>';
                            list.appendChild(div);
                        });
                    }
                })
                .catch(e => console.error("Data error:", e));
        }
        function sync() {
            const url = document.getElementById('sub-url').value;
            if (!url) return;
            fetch('shuka/sync?url=' + encodeURIComponent(url)).then(() => {
                alert('Обновление запущено...');
                setTimeout(updateData, 3000);
            });
        }
        function selectServer(tag) {
            fetch('shuka/select?tag=' + encodeURIComponent(tag)).then(() => {
                setTimeout(updateData, 1000);
            });
        }
        window.onload = () => { setInterval(updateData, 5000); updateData(); };
    </script>
</head>
<body>
    <div class="card">
        <div class="header">
            <div style="display:flex; align-items:center; gap:10px;">
                <h2 style="margin:0;">🚀 Shuka Hybrid</h2>
                <span style="font-size:10px; color:var(--shuka-accent); border:1px solid; padding:2px 6px; border-radius:4px;">sing-box 1.13</span>
            </div>
            <div style="display:flex; gap: 8px;">
                <a href="shuka/start" class="btn btn-primary">СТАРТ</a>
                <a href="shuka/stop" class="btn btn-stop">СТОП</a>
            </div>
        </div>

        <div class="stats-grid">
            <div class="stat-card"><span id="rx-val" class="stat-val">0.00 MB</span><span class="stat-label">Входящий</span></div>
            <div class="stat-card"><span id="tx-val" class="stat-val">0.00 MB</span><span class="stat-label">Исходящий</span></div>
            <div class="stat-card"><span id="ip-badge" class="stat-val">---</span><span class="stat-label">Внешний IP</span></div>
            <div class="stat-card"><span id="status-label" class="stat-val" style="color:var(--danger)">---</span><span class="stat-label">Статус</span></div>
        </div>

        <div class="main-layout">
            <div>
                <h3>🔌 Подписка</h3>
                <input type="text" id="sub-url" placeholder="URL подписки..." value="]]..sub_url..[[">
                <button class="btn btn-sync" onclick="sync()">ОБНОВИТЬ СПИСОК</button>
                
                <h3 style="margin-top:20px;">📋 Логи Sing-box</h3>
                <pre id="log-output">]] .. util.exec("logread | grep -i sing-box | tail -n 10") .. [[</pre>
            </div>
            <div>
                <h3>🌍 Доступные серверы</h3>
                <div id="server-list" class="server-list">Загрузка...</div>
            </div>
        </div>
    </div>
</body>
</html>
]])
end

function action_start()
    os.execute("/etc/init.d/sing-box enable")
    os.execute("/etc/init.d/sing-box start &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end

function action_stop()
    os.execute("/etc/init.d/sing-box stop &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end
