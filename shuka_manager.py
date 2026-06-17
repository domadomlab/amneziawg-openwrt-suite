#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse
import base64
import sys
import os
import re

CONFIG_PATH = "/etc/sing-box/config.json"
TEMPLATE_PATH = "/etc/sing-box/config.json.template"
SUB_URL_FILE = "/etc/sing-box/sub_url.txt"
AMNEZIA_STORAGE = "/etc/sing-box/amnezia_profiles.json"

def load_json(path, default=None):
    if os.path.exists(path):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except: pass
    return default if default is not None else {}

def save_json(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def fetch_subscription(url):
    try:
        headers = {'User-Agent': 'v2rayNG/1.8.5'}
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as response:
            data = response.read().decode('utf-8').strip()
            try:
                # Add padding if missing
                missing_padding = len(data) % 4
                if missing_padding:
                    data += '=' * (4 - missing_padding)
                decoded = base64.b64decode(data).decode('utf-8')
                return decoded.splitlines()
            except:
                return data.splitlines()
    except Exception as e:
        print(f"Error fetching subscription: {e}")
        return None

def parse_link(link):
    try:
        if link.startswith("vless://"):
            m = re.match(r"vless://([^@]+)@([^:]+):(\d+)\?([^#]+)(#.+)?", link)
            if not m: return None
            uuid, host, port, params_raw, tag = m.groups()
            tag = urllib.parse.unquote(tag[1:]) if tag else "VLESS-Server"
            params = dict(urllib.parse.parse_qsl(params_raw))
            outbound = {
                "type": "vless",
                "tag": tag,
                "server": host,
                "server_port": int(port),
                "uuid": uuid,
                "flow": params.get("flow", ""),
                "tls": {
                    "enabled": params.get("security") in ["tls", "reality"],
                    "server_name": params.get("sni", ""),
                    "utls": {"enabled": True, "fingerprint": params.get("fp", "chrome")}
                }
            }
            if params.get("security") == "reality":
                outbound["tls"]["reality"] = {
                    "enabled": True,
                    "public_key": params.get("pbk", ""),
                    "short_id": params.get("sid", "")
                }
            return outbound
        elif link.startswith("ss://"):
            # ss://BASE64#TAG
            m = re.match(r"ss://([^#]+)(#.+)?", link)
            if not m: return None
            data, tag = m.groups()
            tag = urllib.parse.unquote(tag[1:]) if tag else "SS-Server"
            decoded = base64.b64decode(data + '=' * (-len(data) % 4)).decode('utf-8')
            # method:password@host:port
            m2 = re.match(r"([^:]+):([^@]+)@([^:]+):(\d+)", decoded)
            if not m2: return None
            method, password, host, port = m2.groups()
            return {
                "type": "shadowsocks",
                "tag": tag,
                "server": host,
                "server_port": int(port),
                "method": method,
                "password": password
            }
        elif link.startswith("trojan://"):
            m = re.match(r"trojan://([^@]+)@([^:]+):(\d+)\?([^#]+)(#.+)?", link)
            if not m: return None
            password, host, port, params_raw, tag = m.groups()
            tag = urllib.parse.unquote(tag[1:]) if tag else "Trojan-Server"
            params = dict(urllib.parse.parse_qsl(params_raw))
            return {
                "type": "trojan",
                "tag": tag,
                "server": host,
                "server_port": int(port),
                "password": password,
                "tls": {
                    "enabled": True,
                    "server_name": params.get("sni", host),
                    "utls": {"enabled": True, "fingerprint": params.get("fp", "chrome")}
                }
            }
    except: return None
    return None

def merge_and_save(shuka_outbounds=None):
    config = load_json(TEMPLATE_PATH, {"outbounds": []})
    if shuka_outbounds is None:
        current = load_json(CONFIG_PATH, {"outbounds": []})
        shuka_outbounds = [o for o in current.get("outbounds", []) if o["type"] in ["vless", "shadowsocks", "trojan"]]
    config["outbounds"] = shuka_outbounds + [o for o in config["outbounds"] if o["type"] not in ["vless", "shadowsocks", "trojan"]]
    if "route" in config and "rules" in config["route"] and shuka_outbounds:
        for rule in config["route"]["rules"]:
            if rule.get("outbound") == "proxy":
                rule["outbound"] = shuka_outbounds[0]["tag"]
                break
    save_json(CONFIG_PATH, config)

def select_server(tag):
    amnezia_profiles = load_json(AMNEZIA_STORAGE, [])
    am_prof = next((p for p in amnezia_profiles if p["tag"] == tag), None)
    if am_prof:
        os.system("/etc/init.d/sing-box stop")
        # Run in background to avoid LuCI timeout/delay
        os.system(f"/usr/bin/amneziawg-switch.sh '{tag}.conf' >/dev/null 2>&1 &")
        return True
    
    config = load_json(CONFIG_PATH)
    updated = False
    if "route" in config and "rules" in config["route"]:
        for rule in config["route"]["rules"]:
            if rule.get("action") == "hijack-dns": continue
            if "outbound" in rule and rule["outbound"] not in ["direct", "dns-out", "block"]:
                rule["outbound"] = tag
                updated = True
    if updated:
        save_json(CONFIG_PATH, config)
        os.system("/usr/bin/amneziawg-stop.sh >/dev/null 2>&1 &") # Stop AWG in background
        return True
    return False

def main():
    if len(sys.argv) < 2: return
    cmd = sys.argv[1]
    if cmd == "sync":
        if not os.path.exists(SUB_URL_FILE): return
        with open(SUB_URL_FILE, 'r') as f: url = f.read().strip()
        links = fetch_subscription(url)
        if links:
            obs = [parse_link(l) for l in links]
            obs = [o for o in obs if o]
            merge_and_save(obs)
            # Save sync timestamp
            import time
            with open("/etc/sing-box/last_sync.txt", "w") as f:
                f.write(time.strftime("%d.%m.%Y %H:%M:%S"))
            print(f"OK: {len(obs)} servers")
            os.system("/etc/init.d/sing-box restart >/dev/null 2>&1 &")
    elif cmd == "select":
        if len(sys.argv) < 3: return
        tag = sys.argv[2]
        if select_server(tag):
            print(f"OK: Selected {tag}")
    elif cmd == "amnezia":
        conf_file = sys.argv[2] if len(sys.argv) > 2 else "/tmp/amnezia_upload.conf"
        if not os.path.exists(conf_file): return
        name = os.path.basename(conf_file).replace(".conf", "")
        if name == "amnezia_upload" or name == "amnezia_test": name = "Amnezia-" + base64.b32encode(os.urandom(3)).decode().strip("=")
        target_conf = f"/etc/amneziawg/profiles/{name}.conf"
        os.system(f"cp {conf_file} {target_conf}")
        profiles = load_json(AMNEZIA_STORAGE, [])
        if not any(p["tag"] == name for p in profiles):
            profiles.append({"tag": name, "type": "amneziawg", "server": "Kernel Mode"})
            save_json(AMNEZIA_STORAGE, profiles)
        os.system("/etc/init.d/sing-box stop >/dev/null 2>&1")
        os.system(f"/usr/bin/amneziawg-switch.sh '{name}.conf' >/dev/null 2>&1 &")
        print(f"OK: Amnezia {name} started")

    elif cmd == "del_amnezia":
        if len(sys.argv) < 3: return
        tag = sys.argv[2]
        profiles = load_json(AMNEZIA_STORAGE, [])
        new_profiles = [p for p in profiles if p["tag"] != tag]
        save_json(AMNEZIA_STORAGE, new_profiles)
        conf_file = f"/etc/amneziawg/profiles/{tag}.conf"
        if os.path.exists(conf_file):
            os.remove(conf_file)
        print(f"OK: Removed {tag}")
        
    elif cmd == "start":
        config = load_json(CONFIG_PATH)
        active_tag = None
        if "route" in config and "rules" in config["route"]:
            for rule in config["route"]["rules"]:
                if rule.get("action") == "hijack-dns": continue
                if "outbound" in rule and rule["outbound"] not in ["direct", "dns-out", "block"]:
                    active_tag = rule["outbound"]
                    break
        if active_tag:
            select_server(active_tag)
            amnezia_profiles = load_json(AMNEZIA_STORAGE, [])
            if not any(p["tag"] == active_tag for p in amnezia_profiles):
                os.system("/etc/init.d/sing-box enable >/dev/null 2>&1")
                os.system("/etc/init.d/sing-box start >/dev/null 2>&1")
                
    elif cmd == "stop":
        os.system("/etc/init.d/sing-box stop >/dev/null 2>&1")
        os.system("/usr/bin/amneziawg-stop.sh >/dev/null 2>&1")

if __name__ == "__main__":
    main()
