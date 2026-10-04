"""Client MCP minimal pour Atlas (popup « Nouvelle tâche », AtlasTask.qml).

  atlas-task cached          thèmes + projets du dernier appel (cache, sans réseau)
  atlas-task meta            thèmes + projets en JSON (mis en cache)
  atlas-task create '<json>' crée une tâche (arguments de l'outil create_task)
  atlas-task create-exam '<json>'
                             crée un devoir (kind, courseId, teacherId, title, date, link,
                             notes, toHandIn) : le MCP n'a pas d'outil pour les évaluations,
                             on passe par l'action web « addExam » de /courses (sans jeton)

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
import urllib.parse
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


def claude_server():
    try:
        return find_server(json.load(open(os.path.expanduser("~/.claude.json")))) or {}
    except (OSError, ValueError):
        return {}


def base_url():
    """Racine de l'appli web (l'URL MCP sans /api/mcp)."""
    url = claude_server().get("url", DEFAULT_URL)
    return url[: -len("/api/mcp")] if url.endswith("/api/mcp") else url.rstrip("/")


def credentials():
    srv = claude_server()
    url = srv.get("url", DEFAULT_URL)
    auth = srv.get("headers", {}).get("Authorization")
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


def courses():
    """Matières de la classe courante, avec leurs profs (API de l'appli web)."""
    try:
        with urllib.request.urlopen(base_url() + "/api/course-options", context=CTX, timeout=10) as r:
            return json.load(r)
    except (urllib.error.URLError, ValueError):
        return []


def meta():
    with Client() as c:
        out = {"themes": c.tool("list_themes", {}), "projects": c.tool("list_projects", {})}
    out["courses"] = courses()
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


def devalue(raw):
    """Décode les données d'une réponse d'action SvelteKit (format devalue, types simples)."""
    arr = json.loads(raw)
    if not isinstance(arr, list):
        return None

    def h(i):
        if not isinstance(i, int) or i < 0:
            return None
        v = arr[i]
        if isinstance(v, dict):
            return {k: h(x) for k, x in v.items()}
        if isinstance(v, list):
            return None if v and isinstance(v[0], str) else [h(x) for x in v]
        return v
    return h(0)


def create_exam(args):
    form = {k: args.get(k) for k in ("kind", "courseId", "teacherId", "title", "date", "link", "notes")}
    form = {k: str(v) for k, v in form.items() if v not in (None, "")}
    if args.get("toHandIn"):
        form["toHandIn"] = "on"
    base = base_url()
    req = urllib.request.Request(base + "/courses?/addExam", urllib.parse.urlencode(form).encode(), {
        "Content-Type": "application/x-www-form-urlencoded",
        "Origin": base,
        "Accept": "application/json",
        "x-sveltekit-action": "true",
    })
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=15) as r:
            res = json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Atlas : erreur HTTP {e.code}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"Atlas injoignable ({e.reason})")
    if res.get("type") == "failure":
        data = devalue(res.get("data", "null")) or {}
        msgs = [m for v in (data.get("errors") or {}).values() for m in (v or [])]
        raise RuntimeError(" ".join(msgs) or "Atlas a refusé le devoir")
    if res.get("type") == "error":
        raise RuntimeError((res.get("error") or {}).get("message", "Erreur d'Atlas"))
    subprocess.Popen([NOTIFY, "-a", "Atlas", "-i", "atlas-homelab",
                      "Devoir ajouté", args.get("title") or args.get("kindLabel", "")])
    return {"ok": True}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if cmd == "cached":
            # Affichage immédiat du popup avant la réponse du serveur
            try:
                out = json.load(open(CACHE))
            except (OSError, ValueError):
                out = {"themes": [], "projects": [], "courses": []}
        elif cmd == "meta":
            out = meta()
        elif cmd == "create-exam" and len(sys.argv) > 2:
            out = create_exam(json.loads(sys.argv[2]))
        elif cmd == "create" and len(sys.argv) > 2:
            out = create(json.loads(sys.argv[2]))
        else:
            raise RuntimeError("usage : atlas-task cached | meta | create '<json>' | create-exam '<json>'")
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
