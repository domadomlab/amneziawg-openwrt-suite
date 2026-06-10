#!/usr/bin/env python3
import json
import urllib.request
import base64
import sys
import os
import re

CONFIG_PATH = "/etc/sing-box/config.json"
TEMPLATE_PATH = "/etc/sing-box/config.json.template"
SUB_URL_FILE = "/etc/sing-box/sub_url.txt"

def fetch_subscription(url):
    try:
        headers = {'User-Agent': 'v2rayNG/1.8.5'}
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as response:
            data = response.read().decode('utf-8').strip()
            try:
                decoded = base64.b64decode(data).decode('utf-8')
                return decoded.splitlines()
            except:
                return data.splitlines()
    except Exception as e:
        print(f"Error fetching subscription: {e}")
        return None

def parse_vless(link):
    try:
        m = re.match(r"vless://([^@]+)@([^:]+):(\d+)\?([^#]+)(#.+)?", link)
        if not m: return None
        uuid, host, port, params_raw, tag = m.groups()
        tag = urllib.parse.unquote(tag[1:]) if tag else "Server"
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
    except: return None

def merge_config(links):
    if not links: return False
    shuka_outbounds = []
    for link in links:
        if link.startswith("vless://"):
            ob = parse_vless(link)
            if ob: shuka_outbounds.append(ob)
    
    try:
        if not os.path.exists(TEMPLATE_PATH): return False
        with open(TEMPLATE_PATH, 'r') as f:
            config = json.load(f)
        
        # Merge outbounds
        config["outbounds"] = shuka_outbounds + [ob for ob in config["outbounds"] if ob["tag"] not in [s["tag"] for s in shuka_outbounds]]
        
        # Set default proxy rule
        if shuka_outbounds and "route" in config and "rules" in config["route"]:
            for rule in config["route"]["rules"]:
                if rule.get("outbound") == "proxy":
                    rule["outbound"] = shuka_outbounds[0]["tag"]
                    break
        
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        return True
    except Exception as e:
        print(f"Error merging config: {e}")
        return False

def select_server(tag):
    try:
        if not os.path.exists(CONFIG_PATH): return False
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            config = json.load(f)
            
        # Update routing rules
        updated = False
        if "route" in config and "rules" in config["route"]:
            for rule in config["route"]["rules"]:
                # ONLY update rules that have outbound field AND NOT hijack-dns
                if rule.get("action") == "hijack-dns":
                    continue
                if "outbound" in rule and rule["outbound"] not in ["direct", "dns-out", "block"]:
                    rule["outbound"] = tag
                    updated = True
        
        if updated:
            with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
                json.dump(config, f, indent=2, ensure_ascii=False)
            return True
        return False
    except Exception as e:
        print(f"Error selecting server: {e}")
        return False

def main():
    if len(sys.argv) < 2: return
    cmd = sys.argv[1]
    
    if cmd == "sync":
        if not os.path.exists(SUB_URL_FILE): return
        with open(SUB_URL_FILE, 'r') as f: url = f.read().strip()
        links = fetch_subscription(url)
        if links and merge_config(links):
            print(f"OK: {len(links)} servers")
            os.system("/etc/init.d/sing-box restart")
            
    elif cmd == "select":
        if len(sys.argv) < 3: return
        tag = sys.argv[2]
        if select_server(tag):
            print(f"OK: Selected {tag}")
            os.system("/etc/init.d/sing-box restart")

if __name__ == "__main__":
    main()
