"""Client MCP minimal pour Atlas (popup « Nouvelle tâche », AtlasTask.qml).

  atlas-task cached          thèmes + projets du dernier appel (cache, sans réseau)
  atlas-task meta            thèmes + projets en JSON (mis en cache)
  atlas-task create '<json>' crée une tâche (arguments de l'outil create_task)

Jeton : $ATLAS_TOKEN, sinon ~/.config/atlas/token, sinon la config MCP de Claude Code
(~/.claude.json, serveur « atlas »). Sortie en JSON sur stdout ; en cas d'échec,
{"error": "..."} et code de retour 1.
"""
import json
import os
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

DEFAULT_URL = "https://atlas.homelab.lan/api/mcp"
CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "atlas-task", "meta.json")
NOTIFY = os.environ.get("ATLAS_NOTIFY", "notify-send")
# CA de Caddy ajoutée au magasin système (security.pki.certificateFiles)
CTX = ssl.create_default_context(cafile="/etc/ssl/certs/ca-certificates.crt")


def find_server(o):
    """Cherche l'entrée « atlas » avec des en-têtes dans la config Claude Code."""
    if isinstance(o, dict):
        a = o.get("atlas")
        if isinstance(a, dict) and "headers" in a:
            return a
        for v in o.values():
            r = find_server(v)
            if r:
                return r
    return None


def credentials():
    url, auth = DEFAULT_URL, None
    try:
        srv = find_server(json.load(open(os.path.expanduser("~/.claude.json"))))
        if srv:
            url = srv.get("url", url)
            auth = srv.get("headers", {}).get("Authorization")
    except (OSError, ValueError):
        pass
    tok = os.environ.get("ATLAS_TOKEN")
    if not tok:
        try:
            tok = open(os.path.expanduser("~/.config/atlas/token")).read().strip()
        except OSError:
            tok = None
    if tok:
        auth = "Bearer " + tok
    if not auth:
        raise RuntimeError("Aucun jeton Atlas (~/.config/atlas/token)")
    return url, auth


class Client:
    def __init__(self):
        self.url, self.auth = credentials()
        self.sid = None
        self.next_id = 1

    def post(self, msg):
        headers = {
            "Authorization": self.auth,
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.sid:
            headers["Mcp-Session-Id"] = self.sid
        req = urllib.request.Request(self.url, json.dumps(msg).encode(), headers)
        try:
            with urllib.request.urlopen(req, context=CTX, timeout=15) as r:
                self.sid = r.headers.get("Mcp-Session-Id") or self.sid
                body = r.read().decode()
                ctype = r.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                raise RuntimeError("Jeton Atlas refusé")
            raise RuntimeError(f"Atlas : erreur HTTP {e.code}")
        except urllib.error.URLError as e:
            raise RuntimeError(f"Atlas injoignable ({e.reason})")
        if "id" not in msg or not body.strip():
            return None
        # Réponse directe (JSON) ou flux SSE : on garde le message qui porte notre id
        if "text/event-stream" in ctype:
            for line in body.splitlines():
                if line.startswith("data:"):
                    try:
                        m = json.loads(line[5:])
                    except ValueError:
                        continue
                    if m.get("id") == msg["id"]:
                        return m
            raise RuntimeError("Atlas : réponse vide")
        return json.loads(body)

    def request(self, method, params):
        msg = {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params}
        self.next_id += 1
        r = self.post(msg)
        if "error" in r:
            raise RuntimeError(r["error"].get("message", "erreur MCP"))
        return r["result"]

    def __enter__(self):
        self.request("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "atlas-task", "version": "1"},
        })
        self.post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return self

    def __exit__(self, *_):
        if self.sid:
            req = urllib.request.Request(self.url, method="DELETE", headers={
                "Authorization": self.auth, "Mcp-Session-Id": self.sid})
            try:
                urllib.request.urlopen(req, context=CTX, timeout=3).close()
            except Exception:
                pass

    def tool(self, name, args):
        res = self.request("tools/call", {"name": name, "arguments": args})
        text = "".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
        if res.get("isError"):
            raise RuntimeError(text or "Atlas a refusé la demande")
        try:
            return json.loads(text)
        except ValueError:
            return text


def meta():
    with Client() as c:
        out = {"themes": c.tool("list_themes", {}), "projects": c.tool("list_projects", {})}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE + ".tmp", "w") as f:
        json.dump(out, f, ensure_ascii=False)
    os.replace(CACHE + ".tmp", CACHE)
    return out


def create(args):
    with Client() as c:
        task = c.tool("create_task", args)
    subprocess.Popen([NOTIFY, "-a", "Atlas", "-i", "atlas-homelab",
                      "Tâche créée", args.get("title", "")])
    return task


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if cmd == "cached":
            # Affichage immédiat du popup avant la réponse du serveur
            try:
                out = json.load(open(CACHE))
            except (OSError, ValueError):
                out = {"themes": [], "projects": []}
        elif cmd == "meta":
            out = meta()
        elif cmd == "create" and len(sys.argv) > 2:
            out = create(json.loads(sys.argv[2]))
        else:
            raise RuntimeError("usage : atlas-task meta | create '<json>'")
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
