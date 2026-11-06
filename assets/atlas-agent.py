#!/usr/bin/env python3
"""Client de l'agent IA d'Atlas (Hermes) pour la fenêtre Quickshell AtlasAgent.qml.

  atlas-agent send <id|0> '<texte>'   envoie un message ; flux NDJSON sur stdout :
                                      {"t":"start","conversationId":N} {"t":"delta","text":…}
                                      {"t":"tool","label":…} {"t":"done"} {"t":"error","message":…}
  atlas-agent stop <id>               arrête la réponse en cours
  atlas-agent load <id>               messages d'une discussion (JSON)
  atlas-agent last                    id de la dernière discussion ouverte (état local) ou 0

Atlas n'a pas d'authentification applicative (VPN seulement) : pas de jeton.
"""
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("ATLAS_URL", "https://atlas.homelab.lan")
CTX = ssl.create_default_context(cafile="/etc/ssl/certs/ca-certificates.crt")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "atlas-agent")


def out(o):
    print(json.dumps(o, ensure_ascii=False), flush=True)


def send(conv, text):
    body = json.dumps({"conversationId": conv or None, "text": text}).encode()
    req = urllib.request.Request(BASE + "/api/agent", body, {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=300) as r:
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                try:
                    e = json.loads(line[5:])
                except ValueError:
                    continue
                if e.get("t") == "start":
                    os.makedirs(STATE, exist_ok=True)
                    open(os.path.join(STATE, "last"), "w").write(str(e["conversationId"]))
                out(e)
    except urllib.error.HTTPError as e:
        out({"t": "error", "message": f"Atlas : erreur HTTP {e.code}"})
    except (urllib.error.URLError, OSError) as e:
        out({"t": "error", "message": f"Atlas injoignable ({getattr(e, 'reason', e)})"})


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "send" and len(sys.argv) >= 4:
        send(int(sys.argv[2]), sys.argv[3])
    elif cmd == "stop" and len(sys.argv) >= 3:
        req = urllib.request.Request(f"{BASE}/api/agent?c={int(sys.argv[2])}", method="DELETE")
        try:
            urllib.request.urlopen(req, context=CTX, timeout=5).close()
        except (urllib.error.URLError, OSError):
            pass
    elif cmd == "load" and len(sys.argv) >= 3:
        try:
            with urllib.request.urlopen(f"{BASE}/api/agent?c={int(sys.argv[2])}", context=CTX, timeout=10) as r:
                d = json.load(r)
            out({"id": d["id"], "title": d.get("title") or "", "messages": [
                {"role": m["role"], "content": m["content"], "error": bool(m.get("error"))}
                for m in d["messages"]]})
        except (urllib.error.URLError, OSError, ValueError):
            out({"id": 0, "messages": []})
    elif cmd == "last":
        try:
            print(int(open(os.path.join(STATE, "last")).read().strip()))
        except (OSError, ValueError):
            print(0)
    else:
        sys.exit(__doc__)


main()
