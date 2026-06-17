module("luci.controller.amneziawg", package.seeall)

function index()
    entry({"admin", "services", "amneziawg"}, call("action_status"), _("AmneziaWG"), 60)
    entry({"admin", "services", "amneziawg", "start"}, call("action_start"), nil).leaf = true
    entry({"admin", "services", "amneziawg", "stop"}, call("action_stop"), nil).leaf = true
    entry({"admin", "services", "amneziawg", "delete"}, call("action_delete"), nil).leaf = true
    entry({"admin", "services", "amneziawg", "upload"}, call("action_upload"), nil).leaf = true
    entry({"admin", "services", "amneziawg", "data"}, call("action_data"), nil).leaf = true
    entry({"admin", "services", "amneziawg", "switch"}, call("action_switch"), nil).leaf = true
    entry({"admin", "services", "amneziawg", "dns"}, call("action_dns"), nil).leaf = true
    entry({"admin", "services", "amneziawg", "rescue"}, call("action_rescue"), nil).leaf = true
end

function action_rescue()
    os.execute("/usr/bin/amneziawg-rescue.sh &")
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_dns()
    local set = luci.http.formvalue("set")
    if set then
        os.execute("/usr/bin/amneziawg-dns.sh " .. set .. " &")
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_switch()
    local name = luci.http.formvalue("name")
    if name then
        os.execute("/usr/bin/amneziawg-switch.sh '" .. name .. "' &")
    end
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "amneziawg"))
end

function action_data()
    local util = require "luci.util"
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local iface = "awg0"
    
    local function format_bytes(bytes)
        bytes = tonumber(bytes) or 0
        if bytes > 1024*1024*1024 then return string.format("%.2f GiB", bytes / (1024*1024*1024))
        elseif bytes > 1024*1024 then return string.format("%.2f MiB", bytes / (1024*1024))
        elseif bytes > 1024 then return string.format("%.2f KiB", bytes / 1024)
        else return bytes .. " B" end
    end

    local handshake = tonumber(util.exec("awg-new show " .. iface .. " latest-handshakes 2>/dev/null | awk '{print $NF}'") or "0") or 0
    local transfer = util.exec("awg-new show " .. iface .. " transfer 2>/dev/null")
    local rx_raw, tx_raw = transfer:match("%S+%s+(%d+)%s+(%d+)")
    local rx = format_bytes(rx_raw)
    local tx = format_bytes(tx_raw)
    
    local ip = util.exec("curl -s --connect-timeout 2 ifconfig.me")
    if ip == "" then ip = "Offline" end
    
    local dns_state = util.exec("/usr/bin/amneziawg-dns.sh status")
    dns_state = dns_state:gsub("%s+", "")
    
    local log_file = "/tmp/awg_health.log"
    local health_log = fs.access(log_file) and util.exec("tail -n 10 " .. log_file) or "..."
    
    local data = {
        handshake = handshake,
        rx = rx,
        tx = tx,
        ip = ip,
        dns = dns_state,
        log = health_log,
        active = (handshake > 0)
    }
    
    http.prepare_content("application/json")
    http.write_json(data)
end

function action_status()
    local sys = require "luci.sys"
    local http = require "luci.http"
    local util = require "luci.util"
    local fs = require "nixio.fs"
    local profiles_dir = "/etc/amneziawg/profiles/"
    local wiki_file = "/etc/amneziawg/WIKI.md"
    
    local profiles = {}
    for file in (fs.dir(profiles_dir) or function() end) do
        if file:match("%.conf$") then
            table.insert(profiles, file)
        end
    end
    table.sort(profiles)

    local wiki_text = fs.access(wiki_file) and util.exec("cat " .. wiki_file) or "..."

    http.prepare_content("text/html")
    http.write([[
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>AmneziaWG 3.2.0 LTS</title>
            <style>
                body { font-family: sans-serif; padding: 20px; background: #f4f4f4; }
                .card { background: white; padding: 25px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 900px; margin: auto; position: relative; }
                .lang-switcher { position: absolute; top: 15px; right: 20px; display: flex; gap: 10px; }
                .flag { cursor: pointer; font-size: 24px; opacity: 0.4; transition: all 0.2s; filter: grayscale(100%); border: 1px solid transparent; border-radius: 4px; padding: 2px; }
                .flag.active { opacity: 1; filter: grayscale(0%); transform: scale(1.2); border-color: #6f42c1; }
                .btn { display: inline-block; width: 190px; padding: 12px 0; margin: 5px; cursor: pointer; border: none; border-radius: 5px; color: white; font-weight: bold; font-size: 13px; text-align: center; transition: all 0.2s; }
                .btn:hover { opacity: 0.8; transform: translateY(-1px); }
                .btn-magic { background: #6f42c1; box-shadow: 0 0 10px rgba(111,66,193,0.3); }
                .btn-stop { background: #6c757d; }
                .btn-refresh { background: #17a2b8; }
                .btn-delete { background: #dc3545; }
                .btn-upload { background: #007bff; }
                .btn-select { background: #f39c12; }
                .btn-small { width: auto; padding: 6px 15px; font-size: 11px; margin: 2px; }
                pre { background: #1e1e1e; color: #00ff00; padding: 15px; border-radius: 6px; font-family: monospace; font-size: 13px; white-space: pre-wrap; }
                .info-badge { background: #e9ecef; padding: 4px 10px; border-radius: 10px; font-weight: bold; }
                details { margin-top: 15px; border: 1px solid #dee2e6; border-radius: 6px; background: #f8f9fa; }
                summary { padding: 12px; cursor: pointer; font-weight: bold; color: #6f42c1; outline: none; list-style: none; }
                summary::-webkit-details-marker { display: none; }
                summary:hover { background: #eef; }
                .wiki-content { padding: 15px; border-top: 1px solid #dee2e6; font-size: 12px; line-height: 1.4; color: #444; }
                .bottom-actions { margin-top: 25px; border-top: 2px solid #eee; padding-top: 20px; display: flex; justify-content: center; align-items: flex-start; flex-wrap: wrap; gap: 10px; }
                #configdata { display: none; }
                .file-name { display: block; margin-top: 5px; font-size: 11px; color: #666; font-style: italic; text-align: center; max-width: 190px; overflow: hidden; }
                .status-header { display: flex; align-items: center; justify-content: center; gap: 15px; margin-bottom: 20px; }
                .led { width: 12px; height: 12px; border-radius: 50%; background: #ccc; box-shadow: 0 0 5px rgba(0,0,0,0.2); transition: all 0.3s; }
                .led-active { background: #2ecc71; box-shadow: 0 0 10px #2ecc71; }
                .led-error { background: #e74c3c; box-shadow: 0 0 10px #e74c3c; }
                .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 20px 0; }
                .stat-card { background: #fcfcfc; border: 1px solid #eee; padding: 15px; border-radius: 8px; text-align: center; }
                .stat-val { font-size: 18px; font-weight: bold; color: #333; display: block; }
                .stat-label { font-size: 11px; color: #888; text-transform: uppercase; }
                .profiles-list { margin-top: 20px; border: 1px solid #eee; border-radius: 8px; overflow: hidden; }
                .profile-item { display: flex; align-items: center; justify-content: space-between; padding: 10px 20px; border-bottom: 1px solid #eee; background: #fff; }
                .profile-item:last-child { border-bottom: none; }
                .profile-item:hover { background: #f9f9f9; }
                .profile-name { font-weight: bold; color: #444; font-size: 13px; }
                .dns-control { display: flex; align-items: center; justify-content: space-between; background: #6f42c1; color: white; padding: 12px 20px; border-radius: 8px; margin: 20px 0; }
                .dns-options { display: flex; gap: 5px; background: rgba(255,255,255,0.1); padding: 3px; border-radius: 6px; }
                .dns-btn { cursor: pointer; padding: 5px 10px; border-radius: 4px; font-size: 11px; font-weight: bold; border: 1px solid transparent; transition: all 0.2s; color: white; opacity: 0.6; }
                .dns-btn:hover { opacity: 1; background: rgba(255,255,255,0.2); }
                .dns-btn.active { opacity: 1; background: #2ecc71; border-color: #27ae60; box-shadow: 0 0 5px rgba(46,204,113,0.5); }
            </style>
            <script>
                const i18n = {
                    ru: { title: "✨ AmneziaWG v4.0.2 LTS ✨",
 start: "🚀 ЗАПУСТИТЬ VPN", stop: "⏹️ ОСТАНОВИТЬ", refresh: "🔄 ОБНОВИТЬ", status_label: "Статус:", health_label: "Журнал (Live):", ip_label: "Внешний IP:", wiki_toggle: "📖 Инструкция (Wiki) [Развернуть]", select_file: "📁 ДОБАВИТЬ ПРОФИЛЬ", file_selected: "✅ ФАЙЛ ВЫБРАН", update_config: "📤 ЗАГРУЗИТЬ", delete_config: "🗑️ УДАЛИТЬ", no_file: "Файл не выбран", confirm_delete: "Удалить этот профиль?", rx: "Входящие (RX)", tx: "Исходящие (TX)", hs: "Handshake", activate: "⚡ АКТИВИРОВАТЬ", profiles_title: "🗂️ БИБЛИОТЕКА ПРОФИЛЕЙ", dns_label: "🛡️ УПРАВЛЕНИЕ DNS", rescue: "🆘 ВОССТАНОВЛЕНИЕ", dns_dot: "DoT (Safe)", dns_xbox: "Xbox (Smart)", dns_off: "Default" },
                    en: { title: "✨ AmneziaWG v4.0.2 LTS ✨", start: "🚀 START VPN", stop: "⏹️ STOP VPN", refresh: "🔄 REFRESH", status_label: "Status:", health_label: "Health Log (Live):", ip_label: "External IP:", wiki_toggle: "📖 Documentation (Wiki) [Expand]", select_file: "📁 ADD PROFILE", file_selected: "✅ FILE SELECTED", update_config: "📤 UPLOAD", delete_config: "🗑️ DELETE", no_file: "No file selected", confirm_delete: "Delete this profile?", rx: "Received (RX)", tx: "Sent (TX)", hs: "Handshake", activate: "⚡ ACTIVATE", profiles_title: "🗂️ PROFILES LIBRARY", dns_label: "🛡️ DNS CONTROL", rescue: "🆘 RESCUE / RESTORE", dns_dot: "DoT (Safe)", dns_xbox: "Xbox (Smart)", dns_off: "Default" },
                    cn: { title: "✨ AmneziaWG v4.0.2 LTS ✨", start: "🚀  启动 VPN", stop: "⏹️ 停止 VPN", refresh: "🔄 刷新", status_label: "状态:", health_label: "日志 (实时):", ip_label: "外部 IP:", wiki_toggle: "📖 技 术文档 (Wiki) [展开]", select_file: "📁 添加配置文件", file_selected: "✅ 已选择文件", update_config: "📤 上传配置", delete_config: "🗑️ 删除", no_file: "未选择文件", confirm_delete: "删除此配置?", rx: "下载 (RX)", tx: " 上传 (TX)", hs: "握手时间", activate: "⚡ 激活", profiles_title: "🗂️ 配置 文件库", dns_label: "🛡️ DNS 控制", rescue: "🆘 紧急恢复", dns_dot: "DoT", dns_xbox: "Xbox", dns_off: "Default" }
                };
                function formatHandshake(seconds) {
                    if (seconds <= 0) return "---";
                    const now = Math.floor(Date.now() / 1000);
                    const diff = now - seconds;
                    if (diff < 60) return diff + "s ago";
                    return Math.floor(diff/60) + "m " + (diff%60) + "s ago";
                }
                function updateData() {
                    fetch('amneziawg/data')
                        .then(r => r.json())
                        .then(data => {
                            const led = document.getElementById('status-led');
                            if (led) led.className = 'led ' + (data.active ? 'led-active' : 'led-error');
                            document.getElementById('rx-val').textContent = data.rx;
                            document.getElementById('tx-val').textContent = data.tx;
                            document.getElementById('hs-val').textContent = formatHandshake(data.handshake);
                            document.getElementById('ip-badge').textContent = data.ip;
                            document.getElementById('health-log').textContent = data.log;
                            
                            // DNS status visualization
                            const modes = ['dot', 'xbox', 'off'];
                            modes.forEach(m => {
                                const btn = document.getElementById('dns-' + m);
                                if (btn) {
                                    if (data.dns === m || (m === 'off' && data.dns === 'default')) {
                                        btn.classList.add('active');
                                    } else {
                                        btn.classList.remove('active');
                                    }
                                }
                            });
                        });
                }
                function setLang(lang) {
                    localStorage.setItem('awg_lang', lang);
                    document.querySelectorAll('.flag').forEach(f => f.classList.remove('active'));
                    const flag = document.getElementById('flag-' + lang);
                    if (flag) flag.classList.add('active');
                    const t = i18n[lang];
                    document.getElementById('main-title').innerHTML = t.title;
                    document.getElementById('btn-start').innerHTML = t.start;
                    document.getElementById('btn-stop').innerHTML = t.stop;
                    document.getElementById('status-label').innerHTML = t.status_label;
                    document.getElementById('health-label').innerHTML = t.health_label;
                    document.getElementById('ip-label').innerHTML = t.ip_label;
                    document.getElementById('wiki-toggle').innerHTML = t.wiki_toggle;
                    document.getElementById('btn-update').innerHTML = t.update_config;
                    document.getElementById('rx-label').innerHTML = t.rx;
                    document.getElementById('tx-label').innerHTML = t.tx;
                    document.getElementById('hs-label').innerHTML = t.hs;
                    document.getElementById('profiles-title').innerHTML = t.profiles_title;
                    document.getElementById('dns-label').innerHTML = t.dns_label;
                    document.getElementById('dns-dot').innerHTML = t.dns_dot;
                    document.getElementById('dns-xbox').innerHTML = t.dns_xbox;
                    document.getElementById('dns-off').innerHTML = t.dns_off;
                    const selectBtn = document.getElementById('select-btn');
                    const fileInput = document.getElementById('configdata');
                    if (selectBtn && fileInput && !fileInput.files[0]) {
                        selectBtn.innerHTML = t.select_file;
                        document.getElementById('file-label').textContent = t.no_file;
                    }
                    document.querySelectorAll('.btn-activate').forEach(b => b.innerHTML = t.activate);
                    document.querySelectorAll('.btn-delete-prof').forEach(b => b.innerHTML = t.delete_config);
                    const resBtn = document.getElementById('btn-rescue');
                    if (resBtn) resBtn.innerHTML = t.rescue;
                }
                function runRescue() {
                    const l = localStorage.getItem('awg_lang') || 'ru';
                    const msg = l === 'ru' ? 'Выполнить экстренное восстановление сетевых настроек?' : 'Run emergency network restore?';
                    if (confirm(msg)) {
                        fetch('amneziawg/rescue').then(() => {
                            alert(l === 'ru' ? 'Запущено! Роутер перезагрузит сеть. Подождите 30 сек.' : 'Started! Router will restart network. Wait 30s.');
                            setTimeout(() => location.reload(), 30000);
                        });
                    }
                }
                function toggleDns(mode) {
                    fetch('amneziawg/dns?set=' + mode).then(() => updateData());
                }
                window.onload = () => { 
                    setLang(localStorage.getItem('awg_lang') || 'ru');
                    setInterval(updateData, 3000);
                    updateData();
                };
            </script>
        </head>
        <body>
            <div class="card">
                <div class="lang-switcher">
                    <span id="flag-ru" class="flag" onclick="setLang('ru')" title="Русский">🇷🇺</span>
                    <span id="flag-en" class="flag" onclick="setLang('en')" title="English">🇺🇸</span>
                    <span id="flag-cn" class="flag" onclick="setLang('cn')" title="中文">🇨🇳</span>
                </div>
                <h2 id="main-title">...</h2>
                <div class="status-header">
                    <div id="status-led" class="led"></div>
                    <span id="status-label" style="font-weight:bold; color:#555;">...</span>
                </div>
                <div class="stats-grid">
                    <div class="stat-card">
                        <span id="rx-val" class="stat-val">0 B</span>
                        <span id="rx-label" class="stat-label">...</span>
                    </div>
                    <div class="stat-card">
                        <span id="tx-val" class="stat-val">0 B</span>
                        <span id="tx-label" class="stat-label">...</span>
                    </div>
                    <div class="stat-card">
                        <span id="hs-val" class="stat-val">---</span>
                        <span id="hs-label" class="stat-label">...</span>
                    </div>
                </div>
                <div class="main-actions" style="display: flex; justify-content: center; gap: 5px; flex-wrap: wrap;">
                    <button id="btn-start" class="btn btn-magic" style="width:170px;" onclick="location.href='amneziawg/start'">...</button>
                    <button id="btn-stop" class="btn btn-stop" style="width:170px;" onclick="location.href='amneziawg/stop'">...</button>
                    <button id="btn-rescue" class="btn" style="width:170px; background:#e67e22;" onclick="runRescue()">...</button>
                </div>
                <div class="dns-control">
                    <span id="dns-label" style="font-weight:bold; font-size:14px;">...</span>
                    <div class="dns-options">
                        <div id="dns-dot" class="dns-btn" onclick="toggleDns('on_dot')">...</div>
                        <div id="dns-xbox" class="dns-btn" onclick="toggleDns('on_xbox')">...</div>
                        <div id="dns-off" class="dns-btn" onclick="toggleDns('off')">...</div>
                    </div>
                </div>
                <h3 id="profiles-title" style="color:#666; margin-top:10px; font-size:16px;">...</h3>
                <div class="profiles-list">
    ]])

    for _, p in ipairs(profiles) do
        http.write([[
            <div class="profile-item">
                <span class="profile-name">]] .. p .. [[</span>
                <div>
                    <button class="btn btn-magic btn-small btn-activate" onclick="location.href='amneziawg/switch?name=]] .. luci.util.pcdata(p) .. [['">⚡</button>
                    <button class="btn btn-delete btn-small btn-delete-prof" onclick="const l=localStorage.getItem('awg_lang')||'ru'; if(confirm(i18n[l].confirm_delete)) location.href='amneziawg/delete?name=]] .. luci.util.pcdata(p) .. [['">🗑️</button>
                </div>
            </div>
        ]])
    end

    http.write([[
                </div>
                <h3 id="health-label">...</h3>
                <pre id="health-log" style="background:#f1f1f1; color:#333; border-left:4px solid #6f42c1; font-size:11px; height:100px; overflow-y:auto;">...</pre>
                <p style="text-align:center;">
                    <span id="ip-label">...</span> 
                    <span id="ip-badge" class="info-badge">?</span>
                </p>
                <div class="bottom-actions">
                    <form method="post" action="amneziawg/upload" enctype="multipart/form-data" style="display: contents;">
                        <div class="upload-group" style="flex-direction: row; gap: 10px;">
                            <label for="configdata" class="btn btn-select" id="select-btn" style="margin:0;">📁</label>
                            <input type="file" name="configdata" id="configdata" onchange="const l=localStorage.getItem('awg_lang')||'ru'; if(this.files[0]) { document.getElementById('select-btn').style.background='#27ae60'; document.getElementById('select-btn').innerHTML=i18n[l].file_selected; document.getElementById('file-label').textContent=this.files[0].name; }">
                            <button id="btn-update" type="submit" class="btn btn-upload" style="margin:0;">...</button>
                        </div>
                        <span id="file-label" class="file-name" style="width:100%;">...</span>
                    </form>
                </div>
                <details>
                    <summary id="wiki-toggle">...</summary>
                    <div class="wiki-content"><pre style="background:transparent; color:#444; padding:0; font-size:12px; border:none;">]] .. wiki_text .. [[</pre></div>
                </details>
            </div>
        </body>
        </html>
    ]])
end

function action_upload()
    local http = require "luci.http"
    local tmp = "/tmp/upload.conf"
    local filename = "new_profile.conf"
    local fp = io.open(tmp, "w")
    http.setfilehandler(function(m, c, e)
        if m and m.file then filename = m.file end
        if c then fp:write(c) end
        if e then fp:close() end
    end)
    http.formvalue("configdata")
    if filename then
        if not filename:match("%.conf$") then filename = filename .. ".conf" end
        os.execute("mv " .. tmp .. " /etc/amneziawg/profiles/\"" .. filename .. "\"")
    end
    http.redirect(luci.dispatcher.build_url("admin", "services", "amneziawg"))
end

function action_delete()
    local name = luci.http.formvalue("name")
    if name then
        os.execute("rm /etc/amneziawg/profiles/\"" .. name .. "\"")
    else
        os.execute("/etc/init.d/amneziawg stop &")
        os.remove("/etc/amneziawg/awg0.conf")
    end
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "amneziawg"))
end

function action_start() 
    os.execute("uci set amneziawg.config.enabled='1' && uci commit amneziawg")
    os.execute("/etc/init.d/amneziawg start &")
    require"luci.http".redirect(require("luci.dispatcher").build_url("admin", "services", "amneziawg")) 
end

function action_stop() 
    os.execute("uci set amneziawg.config.enabled='0' && uci commit amneziawg")
    os.execute("/etc/init.d/amneziawg stop &")
    require"luci.http".redirect(require("luci.dispatcher").build_url("admin", "services", "amneziawg")) 
end
