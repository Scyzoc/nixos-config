{ pkgs, ... }:

let
  NOTIFY = "${pkgs.libnotify}/bin/notify-send";
  BRAVE  = "${pkgs.brave}/bin/brave";

  # ── Formulaire HTML/CSS/JS (fichier séparé pour éviter les problèmes d'indentation Nix) ──
  htmlFile = pkgs.writeText "notion-todo.html" ''
    <!DOCTYPE html>
    <html lang="fr">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Nouvelle tâche</title>
    <style>
    *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
    :root{
      --s:rgba(255,255,255,0.055);
      --sh:rgba(255,255,255,0.09);
      --b:rgba(255,255,255,0.08);
      --bh:rgba(255,255,255,0.28);
      --t:#e8eaf6;
      --m:rgba(255,255,255,0.38);
      --r:11px;
    }
    html,body{
      height:100%;
      font-family:Inter,-apple-system,BlinkMacSystemFont,Roboto,sans-serif;
      background:#111118;
      color:var(--t);font-size:13px;overflow-y:auto;
    }
    ::-webkit-scrollbar{width:4px}
    ::-webkit-scrollbar-track{background:transparent}
    ::-webkit-scrollbar-thumb{background:rgba(255,255,255,0.15);border-radius:2px}
    .wrap{max-width:540px;margin:0 auto;padding:18px 22px 26px}
    .hdr{display:flex;align-items:center;gap:10px;margin-bottom:20px}
    .hdr-ic{
      width:30px;height:30px;background:rgba(255,255,255,0.07);
      border:1px solid rgba(255,255,255,0.12);border-radius:8px;
      display:flex;align-items:center;justify-content:center;font-size:16px;
    }
    .hdr h1{font-size:16px;font-weight:600;letter-spacing:-0.2px}
    .notion-logo{margin-left:auto;flex-shrink:0;width:28px;height:28px;overflow:hidden;border-radius:6px}
    .notion-logo svg{width:28px!important;height:28px!important;display:block}
    .sec{margin-bottom:13px}
    .lbl{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:0.7px;color:var(--m);margin-bottom:7px}
    .lbl .opt{text-transform:none;letter-spacing:0;font-weight:400;color:rgba(255,255,255,0.2)}
    .tgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:7px}
    .tc{
      background:var(--s);border:1.5px solid var(--b);border-radius:var(--r);
      padding:9px 11px;cursor:pointer;
      transition:background .12s,border-color .12s,transform .1s,box-shadow .12s;
      display:flex;align-items:center;gap:7px;
      font-size:12.5px;font-weight:500;user-select:none;-webkit-user-select:none;
    }
    .tc:hover{background:var(--sh);border-color:rgba(255,255,255,0.16);transform:translateY(-1px)}
    .tc.on{
      background:var(--tc-bg,rgba(255,255,255,0.1));
      border-color:var(--tc-c,rgba(255,255,255,0.5));
      color:var(--tc-c,white);
      box-shadow:0 0 16px var(--tc-g,transparent);
    }
    .tc-i{font-size:15px}
    .sel-w{position:relative}
    select,input[type="text"],textarea,input[type="date"]{
      width:100%;padding:9px 13px;background:var(--s);border:1.5px solid var(--b);
      border-radius:var(--r);color:var(--t);font-size:13px;font-family:inherit;outline:none;
      transition:border-color .12s;
    }
    select{cursor:pointer;appearance:none;-webkit-appearance:none;padding-right:30px}
    select:focus,input[type="text"]:focus,textarea:focus,input[type="date"]:focus{border-color:var(--bh)}
    select option{background:#16162a}
    .sel-ar{position:absolute;right:11px;top:50%;transform:translateY(-50%);color:var(--m);pointer-events:none;font-size:9px}
    input::placeholder,textarea::placeholder{color:var(--m)}
    textarea{resize:vertical;min-height:54px}
    .drow{display:grid;grid-template-columns:repeat(3,1fr);gap:7px;margin-bottom:7px}
    .db{
      background:var(--s);border:1.5px solid var(--b);border-radius:var(--r);
      padding:8px 6px;cursor:pointer;text-align:center;
      transition:background .12s,border-color .12s;user-select:none;-webkit-user-select:none;
    }
    .db:hover{background:var(--sh);border-color:rgba(255,255,255,0.16)}
    .db.on{border-color:#60a5fa;background:rgba(96,165,250,0.1)}
    .db-l{font-size:11.5px;font-weight:600;display:block}
    .db-d{font-size:10px;color:var(--m);display:block;margin-top:1px}
    .db.on .db-l{color:#60a5fa}
    .db.on .db-d{color:rgba(96,165,250,0.6)}
    .row2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
    .lvlrow{display:flex;gap:6px}
    .lc{
      flex:1;background:var(--s);border:1.5px solid var(--b);border-radius:var(--r);
      padding:9px 5px;cursor:pointer;text-align:center;
      transition:all .12s;user-select:none;-webkit-user-select:none;
    }
    .lc:hover{background:var(--sh);border-color:rgba(255,255,255,0.16)}
    .lc-n{font-size:17px;font-weight:700;display:block}
    .lc-t{font-size:10px;color:var(--m);display:block;margin-top:1px}
    .lc.g{border-color:#4ade80;background:rgba(74,222,128,0.08)}
    .lc.g .lc-n{color:#4ade80}
    .lc.y{border-color:#fbbf24;background:rgba(251,191,36,0.08)}
    .lc.y .lc-n{color:#fbbf24}
    .lc.r{border-color:#f87171;background:rgba(248,113,113,0.08)}
    .lc.r .lc-n{color:#f87171}
    .sub-btn{
      width:100%;padding:11px;
      background:linear-gradient(135deg,rgba(96,165,250,0.2) 0%,rgba(167,139,250,0.2) 100%);
      border:1.5px solid rgba(96,165,250,0.32);border-radius:var(--r);
      color:#fff;font-size:13.5px;font-weight:600;font-family:inherit;
      cursor:pointer;transition:all .15s;margin-top:6px;letter-spacing:0.2px;
    }
    .sub-btn:hover:not(:disabled){
      background:linear-gradient(135deg,rgba(96,165,250,0.35) 0%,rgba(167,139,250,0.35) 100%);
      border-color:rgba(96,165,250,0.52);
      box-shadow:0 4px 18px rgba(96,165,250,0.14);transform:translateY(-1px);
    }
    .sub-btn:disabled{opacity:0.4;cursor:not-allowed;transform:none!important}
    .div{height:1px;background:var(--b);margin:2px 0 13px}
    .hidden{display:none!important}
    .toast{
      position:fixed;bottom:18px;left:50%;
      transform:translateX(-50%) translateY(8px);
      padding:8px 18px;border-radius:20px;
      font-size:12.5px;font-weight:500;
      opacity:0;transition:opacity .22s,transform .22s;pointer-events:none;
    }
    .toast.ok{background:rgba(74,222,128,0.16);border:1px solid #4ade80;color:#4ade80}
    .toast.err{background:rgba(248,113,113,0.16);border:1px solid #f87171;color:#f87171}
    .toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
    </style>
    </head>
    <body>
    <div class="wrap">
    <div class="hdr">
      <div class="hdr-ic"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.85)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></div>
      <h1>Nouvelle t&acirc;che</h1>
      <div class="notion-logo">${builtins.readFile ../assets/notion-logo.svg}</div>
    </div>
    <div class="sec">
      <div class="lbl">Type</div>
      <div class="tgrid">
        <div class="tc" data-key="general" style="--tc-c:#60a5fa;--tc-bg:rgba(96,165,250,0.11);--tc-g:rgba(96,165,250,0.18)">
          <span class="tc-i">&#128203;</span> G&eacute;n&eacute;ral
        </div>
        <div class="tc" data-key="projet" style="--tc-c:#a78bfa;--tc-bg:rgba(167,139,250,0.11);--tc-g:rgba(167,139,250,0.18)">
          <span class="tc-i">&#128193;</span> Projet
        </div>
        <div class="tc" data-key="assetto" style="--tc-c:#f87171;--tc-bg:rgba(248,113,113,0.11);--tc-g:rgba(248,113,113,0.18)">
          <span class="tc-i">&#127950;</span> Assetto
        </div>
        <div class="tc" data-key="discord" style="--tc-c:#818cf8;--tc-bg:rgba(129,140,248,0.11);--tc-g:rgba(129,140,248,0.18)">
          <span class="tc-i">&#128172;</span> Discord
        </div>
        <div class="tc" data-key="questions" style="--tc-c:#fbbf24;--tc-bg:rgba(251,191,36,0.11);--tc-g:rgba(251,191,36,0.18)">
          <span class="tc-i">&#10067;</span> Questions
        </div>
        <div class="tc" data-key="euro" style="--tc-c:#fb923c;--tc-bg:rgba(251,146,60,0.11);--tc-g:rgba(251,146,60,0.18)">
          <span class="tc-i">&#128176;</span> Euro
        </div>
      </div>
    </div>
    <div class="sec hidden" id="sec-sub">
      <div class="lbl">Sous-type <span class="opt">&mdash; optionnel</span></div>
      <div class="sel-w">
        <select id="subtype"><option value="">&#8212; Choisir &#8212;</option></select>
        <span class="sel-ar">&#9660;</span>
      </div>
    </div>
    <div class="div"></div>
    <div class="sec">
      <div class="lbl">Titre</div>
      <input type="text" id="titre" placeholder="Nom de la t&acirc;che..." autofocus>
    </div>
    <div class="sec">
      <div class="lbl">Description <span class="opt">&mdash; optionnel</span></div>
      <textarea id="desc" placeholder="D&eacute;tails suppl&eacute;mentaires..."></textarea>
    </div>
    <div class="div"></div>
    <div class="sec">
      <div class="lbl">Date pr&eacute;vue</div>
      <div class="drow">
        <div class="db on" data-iso="__TODAY__">
          <span class="db-l">Aujourd&rsquo;hui</span>
          <span class="db-d">__TODAY_FR__</span>
        </div>
        <div class="db" data-iso="__TOMORROW__">
          <span class="db-l">Demain</span>
          <span class="db-d">__TOMORROW_FR__</span>
        </div>
        <div class="db" data-iso="__DAYAFTER__">
          <span class="db-l">Apr&egrave;s-demain</span>
          <span class="db-d">__DAYAFTER_FR__</span>
        </div>
      </div>
      <input type="date" id="date" value="__TODAY__">
    </div>
    <div class="row2">
      <div class="sec">
        <div class="lbl">Urgence</div>
        <div class="lvlrow">
          <div class="lc" data-grp="u" data-val="1"><span class="lc-n">1</span><span class="lc-t">Faible</span></div>
          <div class="lc" data-grp="u" data-val="2"><span class="lc-n">2</span><span class="lc-t">Moyen</span></div>
          <div class="lc" data-grp="u" data-val="3"><span class="lc-n">3</span><span class="lc-t">Urgent</span></div>
        </div>
      </div>
      <div class="sec">
        <div class="lbl">Impact</div>
        <div class="lvlrow">
          <div class="lc" data-grp="i" data-val="1"><span class="lc-n">1</span><span class="lc-t">Faible</span></div>
          <div class="lc" data-grp="i" data-val="2"><span class="lc-n">2</span><span class="lc-t">Moyen</span></div>
          <div class="lc" data-grp="i" data-val="3"><span class="lc-n">3</span><span class="lc-t">Critique</span></div>
        </div>
      </div>
    </div>
    <button class="sub-btn" id="btn" onclick="doSubmit()">Ajouter la t&acirc;che</button>
    </div>
    <div class="toast" id="toast"></div>
    <script>
    var SUBS = __SUBS__;
    var selType = null, selDate = "__TODAY__", selU = null, selI = null;

    document.querySelectorAll(".tc").forEach(function(el) {
      el.addEventListener("click", function() {
        document.querySelectorAll(".tc").forEach(function(c) { c.classList.remove("on"); });
        el.classList.add("on");
        selType = el.dataset.key;
        var sec = document.getElementById("sec-sub");
        var sel = document.getElementById("subtype");
        var opts = SUBS[selType] || [];
        while (sel.options.length > 0) sel.remove(0);
        sel.add(new Option("— Choisir —", ""));
        if (opts.length > 0) {
          opts.forEach(function(o) { sel.add(new Option(o, o)); });
          sec.classList.remove("hidden");
        } else {
          sec.classList.add("hidden");
        }
      });
    });

    document.querySelectorAll(".db").forEach(function(el) {
      el.addEventListener("click", function() {
        document.querySelectorAll(".db").forEach(function(b) { b.classList.remove("on"); });
        el.classList.add("on");
        selDate = el.dataset.iso;
        document.getElementById("date").value = selDate;
      });
    });
    document.getElementById("date").addEventListener("change", function() {
      document.querySelectorAll(".db").forEach(function(b) { b.classList.remove("on"); });
      selDate = this.value;
    });

    document.querySelectorAll(".lc").forEach(function(el) {
      el.addEventListener("click", function() {
        var grp = el.dataset.grp, val = parseInt(el.dataset.val);
        document.querySelectorAll(".lc").forEach(function(c) {
          if (c.dataset.grp === grp) c.classList.remove("g","y","r");
        });
        el.classList.add(val === 1 ? "g" : val === 2 ? "y" : "r");
        if (grp === "u") selU = val; else selI = val;
      });
    });

    function toast(msg, type) {
      var t = document.getElementById("toast");
      t.textContent = msg;
      t.className = "toast " + type + " show";
      setTimeout(function() { t.classList.remove("show"); }, 3000);
    }

    function doSubmit() {
      if (!selType)  { toast("Sélectionner un type", "err"); return; }
      var titre = document.getElementById("titre").value.trim();
      if (!titre)    { toast("Titre requis", "err"); return; }
      if (!selU)     { toast("Sélectionner une urgence", "err"); return; }
      if (!selI)     { toast("Sélectionner un impact", "err"); return; }
      if (!selDate)  { toast("Sélectionner une date", "err"); return; }
      var btn = document.getElementById("btn");
      btn.disabled = true; btn.textContent = "Envoi...";
      fetch("/submit", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          type: selType,
          subtype: document.getElementById("subtype").value,
          titre: titre,
          desc: document.getElementById("desc").value.trim(),
          date: selDate,
          urgence: selU,
          impact: selI
        })
      })
      .then(function(r) { return r.json(); })
      .then(function(r) {
        if (r.ok) {
          toast("Tâche ajoutée !", "ok");
        } else {
          toast(r.err || "Erreur", "err");
          btn.disabled = false; btn.textContent = "Ajouter la tâche";
        }
      })
      .catch(function() {
        toast("Erreur réseau", "err");
        btn.disabled = false; btn.textContent = "Ajouter la tâche";
      });
    }
    </script>
    </body>
    </html>
  '';

  # ── Script Python : serveur HTTP local + appel API Notion ──
  app = pkgs.writeText "notion-todo-app.py" ''
    import http.server, json, os, subprocess, socketserver, threading, time
    import urllib.request, urllib.error, random, sys
    from datetime import date, timedelta

    NOTIFY    = "${NOTIFY}"
    BRAVE     = "${BRAVE}"
    HTML_FILE = "${htmlFile}"

    TOKEN_FILE = os.path.expanduser("~/.config/notion/token")
    DB_ID = "ID_CENSURE"

    try:
        with open(TOKEN_FILE) as f:
            TOKEN = f.read().strip()
    except FileNotFoundError:
        subprocess.run([NOTIFY, "Notion", "Token manquant : ~/.config/notion/token", "-t", "5000"])
        sys.exit(1)

    PORT  = random.randint(8400, 8499)
    today = date.today()

    TODAY    = today.isoformat()
    TOMORROW = (today + timedelta(days=1)).isoformat()
    DAYAFTER = (today + timedelta(days=2)).isoformat()
    TODAY_FR    = today.strftime("%d/%m")
    TOMORROW_FR = (today + timedelta(days=1)).strftime("%d/%m")
    DAYAFTER_FR = (today + timedelta(days=2)).strftime("%d/%m")

    TYPES = {
        "general":   ("UUID_CENSURE", "General"),
        "projet":    ("UUID_CENSURE", "Projet"),
        "assetto":   ("UUID_CENSURE", "Assetto Corsa"),
        "discord":   ("UUID_CENSURE", "Discord"),
        "questions": ("UUID_CENSURE", "Questions"),
        "euro":      ("UUID_CENSURE", "€"),
    }

    SUBTYPES = {
        "general": {
            "field": "Type Générale", "kind": "relation",
            "opts": {
                "Notion":        "UUID_CENSURE",
                "Bug":           "UUID_CENSURE",
                "Apprendre":     "UUID_CENSURE",
                "Configuration": "UUID_CENSURE",
                "Installation":  "UUID_CENSURE",
                "Démarches":     "UUID_CENSURE",
                "YouTube":       "UUID_CENSURE",
                "Mise à Jour":   "UUID_CENSURE",
                "Imprimer":      "UUID_CENSURE",
            }
        },
        "questions": {
            "field": "Type Générale", "kind": "relation",
            "opts": {
                "Notion":        "UUID_CENSURE",
                "Bug":           "UUID_CENSURE",
                "Apprendre":     "UUID_CENSURE",
                "Configuration": "UUID_CENSURE",
                "Installation":  "UUID_CENSURE",
                "Démarches":     "UUID_CENSURE",
                "YouTube":       "UUID_CENSURE",
                "Mise à Jour":   "UUID_CENSURE",
                "Imprimer":      "UUID_CENSURE",
            }
        },
        "assetto": {
            "field": "Type Assetto", "kind": "multi_select",
            "opts": {
                "\U0001f41e Bug":                              None,
                "\U0001f4ac Demande de fonctionnalité":        None,
                "\U0001f485 Perfectionnement":                 None,
                "\U0001f9e0 Apprendre":                        None,
                "\U0001f4ab MàJ":                              None,
                "\U0001f3ac Réalisation":                      None,
            }
        },
        "discord": {
            "field": "Type Discord", "kind": "multi_select",
            "opts": {
                "\U0001f41e Bug":                              None,
                "\U0001f4ac Demande de fonctionnalité":        None,
                "\U0001f485 Perfectionnement":                 None,
                "\U0001f9e0 Apprendre":                        None,
                "\U0001f4ab MàJ":                              None,
                "\U0001f4a1 Idée":                             None,
            }
        },
        "projet": {
            "field": "__desc__", "kind": "desc_prefix",
            "opts": {
                "\U0001f3a8 Interface Notion":              None,
                "\U0001f4aa Application Notion musculation": None,
                "\U0001f427 NixOS / Hyprland":              None,
                "\U0001f3d7️ Rénovation Chambre":  None,
                "⚙️ Backend":                      None,
                "\U0001f310 Portfolio":                      None,
                "✈️ Voyage":                       None,
                "\U0001f41b Site 404´S":                None,
            }
        },
        "euro": {
            "field": "Type €", "kind": "relation",
            "opts": {
                "Vinted":          "UUID_CENSURE",
                "Mémo Vinted":    "UUID_CENSURE",
                "Démarches":      "UUID_CENSURE",
                "Excel":           "UUID_CENSURE",
                "Gemini":          "UUID_CENSURE",
                "Seiko":           "UUID_CENSURE",
                "Notion":          "UUID_CENSURE",
                "YouTube":         "UUID_CENSURE",
                "Apprendre":       "UUID_CENSURE",
            }
        },
    }

    js_subs = {k: list(v["opts"].keys()) for k, v in SUBTYPES.items()}
    SUBS_JSON = json.dumps(js_subs)

    # Chaque projet a sa propre base de données avec son propre schéma
    PROJECTS = {
        "\U0001f3a8 Interface Notion": {
            "db": "ID_CENSURE",
            "title": "Nom",   "date": "Prévu",  "text": None,
            "status": "État", "status_val": "Pas commencé",
            "urg": "Urgence", "imp": "Impact",
        },
        "\U0001f4aa Application Notion musculation": {
            "db": "ID_CENSURE",
            "title": "Name",     "date": "Prévu",  "text": "Description",
            "status": "Status",  "status_val": "Not started",
            "urg": "Urgence", "imp": "Impact",
        },
        "\U0001f427 NixOS / Hyprland": {
            "db": "ID_CENSURE",
            "title": "Name",    "date": "Prévu",  "text": "Description",
            "status": "Status", "status_val": "Not started",
            "urg": "Urgence", "imp": "Impact",
        },
        "\U0001f3d7️ Rénovation Chambre": {
            "db": "ID_CENSURE",
            "title": "Tâche",   "date": "Prévu",  "text": "Notes",
            "status": "Status", "status_val": "Not started",
            "urg": "Urgence", "imp": "Impact",
        },
        "⚙️ Backend": {
            "db": "ID_CENSURE",
            "title": "Name",  "date": "Prévu",  "text": None,
            "status": "État", "status_val": "À faire",
            "urg": "Urgence", "imp": "Impact",
        },
        "\U0001f310 Portfolio": {
            "db": "ID_CENSURE",
            "title": "Nom",   "date": "Prévu",  "text": None,
            "status": "État", "status_val": "Pas commencé",
            "urg": "Urgence", "imp": "Impact",
        },
        "✈️ Voyage": {
            "db": "ID_CENSURE",
            "title": "Name", "date": "Prévu", "text": None,
            "status": None,  "status_val": None,
            "urg": "Urgence", "imp": "Impact",
        },
        "\U0001f41b Site 404´S": {
            "db": "ID_CENSURE",
            "title": "Tâche", "date": "Prévu", "text": "Description",
            "status": "Status", "status_val": "Not started",
            "urg": "Urgence", "imp": "Impact",
        },
    }

    def _notion_post(db, props):
        payload = json.dumps({"parent": {"database_id": db}, "properties": props}).encode()
        req = urllib.request.Request(
            "https://api.notion.com/v1/pages",
            data=payload,
            headers={
                "Authorization": "Bearer " + TOKEN,
                "Notion-Version": "2022-06-28",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req) as r:
                json.loads(r.read())
                return {"ok": True}
        except urllib.error.HTTPError as e:
            err = json.loads(e.read())
            return {"ok": False, "err": err.get("message", "Erreur HTTP")}
        except Exception as e:
            return {"ok": False, "err": str(e)}

    def add_task(data):
        tkey  = data.get("type", "")
        titre = data.get("titre", "").strip()
        sub   = data.get("subtype", "").strip()
        desc  = data.get("desc", "").strip()
        ddate = data.get("date", "")
        urg   = str(data.get("urgence", 1))
        imp   = str(data.get("impact",  1))

        if tkey not in TYPES:
            return {"ok": False, "err": "Type invalide"}
        if not titre:
            return {"ok": False, "err": "Titre requis"}

        # Projet → base de données spécifique au projet
        if tkey == "projet" and sub and sub in PROJECTS:
            p = PROJECTS[sub]
            props = {p["title"]: {"title": [{"text": {"content": titre}}]}}
            if p["date"] and ddate:
                props[p["date"]] = {"date": {"start": ddate}}
            if p["text"] and desc:
                props[p["text"]] = {"rich_text": [{"text": {"content": desc}}]}
            if p["status"]:
                props[p["status"]] = {"status": {"name": p["status_val"]}}
            if p["urg"]:
                props[p["urg"]] = {"select": {"name": urg}}
            if p["imp"]:
                props[p["imp"]] = {"select": {"name": imp}}
            return _notion_post(p["db"], props)

        # Autres types → base TODO principale
        notion_id = TYPES[tkey][0]
        props = {
            "Nom":        {"title":   [{"text": {"content": titre}}]},
            "Type TO DO": {"relation":[{"id": notion_id}]},
            "Urgence":    {"select":  {"name": urg}},
            "Impact":     {"select":  {"name": imp}},
            "État":       {"status":  {"name": "À faire"}},
            "Prévu":      {"date":    {"start": ddate}},
        }
        if desc:
            props["Description"] = {"rich_text": [{"text": {"content": desc}}]}
        if tkey in SUBTYPES and sub:
            si = SUBTYPES[tkey]
            if si["kind"] == "relation" and sub in si["opts"] and si["opts"][sub]:
                props[si["field"]] = {"relation": [{"id": si["opts"][sub]}]}
            elif si["kind"] == "multi_select":
                props[si["field"]] = {"multi_select": [{"name": sub}]}
        return _notion_post(DB_ID, props)

    with open(HTML_FILE, encoding="utf-8") as f:
        HTML_TMPL = f.read()

    def get_html():
        return (HTML_TMPL
            .replace("__SUBS__",        SUBS_JSON)
            .replace("__TODAY_FR__",    TODAY_FR)
            .replace("__TOMORROW_FR__", TOMORROW_FR)
            .replace("__DAYAFTER_FR__", DAYAFTER_FR)
            .replace("__TODAY__",       TODAY)
            .replace("__TOMORROW__",    TOMORROW)
            .replace("__DAYAFTER__",    DAYAFTER)
        )

    proc = [None]

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a): pass

        def do_GET(self):
            body = get_html().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type",   "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            data   = json.loads(self.rfile.read(length))
            result = add_task(data)
            if result["ok"]:
                subprocess.run([NOTIFY, "Notion",
                    "✅ " + data.get("titre", "Tâche"),
                    "-i", "applications-office", "-t", "4000"])
                def _close():
                    time.sleep(1.4)
                    if proc[0]:
                        proc[0].terminate()
                threading.Thread(target=_close, daemon=True).start()
            body = json.dumps(result).encode()
            self.send_response(200)
            self.send_header("Content-Type",   "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    socketserver.TCPServer.allow_reuse_address = True
    server = socketserver.TCPServer(("127.0.0.1", PORT), Handler)
    t = threading.Thread(target=server.serve_forever)
    t.daemon = True
    t.start()

    data_dir = os.path.join(os.path.expanduser("~"), ".local", "share", "notion-todo-brave")
    os.makedirs(data_dir, exist_ok=True)
    env = os.environ.copy()
    env["NIXOS_OZONE_WL"] = ""
    try:
        proc[0] = subprocess.Popen([
            BRAVE,
            "--app=http://127.0.0.1:" + str(PORT),
            "--window-size=560,700",
            "--class=notion-todo",
            "--user-data-dir=" + data_dir,
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            "--disable-sync",
            "--ozone-platform=x11",
        ], env=env)
        proc[0].wait()
    finally:
        server.shutdown()
  '';

  notion-todo = pkgs.writeShellScriptBin "notion-todo" ''
    if pgrep -f "notion-todo-app.py" > /dev/null 2>&1; then exit 0; fi
    exec ${pkgs.python3}/bin/python3 ${app}
  '';
in
{
  home.packages = [ notion-todo ];
}
