#!/usr/bin/env python3
"""Récupération d'icône et de nom pour la commande `webapp` (modules/webapps.nix).

  webapp.py fetch URL DEST   meilleure icône du site → DEST.svg ou DEST.png
                             stdout : chemin de l'icône, puis nom suggéré
  webapp.py slug NOM         identifiant ascii (« Mon Appli » → mon-appli)
"""
import io
import json
import re
import ssl
import sys
import unicodedata
import urllib.parse
import urllib.request
from html.parser import HTMLParser

from PIL import Image

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/130.0 Safari/537.36")
# Magasin système : contient aussi la racine Caddy du homelab
CTX = ssl.create_default_context(cafile="/etc/ssl/certs/ca-certificates.crt")
SVG = 10_000  # score d'une icône vectorielle (toujours préférée)


def get(url, limite=5_000_000):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=10, context=CTX) as r:
        return r.geturl(), r.headers.get_content_type(), r.read(limite)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.meta, self.titre, self._dans_titre = [], {}, "", False

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if tag == "link":
            self.links.append(a)
        elif tag == "meta" and (a.get("property") or a.get("name")):
            self.meta[(a.get("property") or a.get("name")).lower()] = a.get("content", "").strip()
        elif tag == "title":
            self._dans_titre = True

    def handle_endtag(self, tag):
        if tag == "title":
            self._dans_titre = False

    def handle_data(self, data):
        if self._dans_titre:
            self.titre += data


def taille(sizes):
    if sizes == "any":
        return SVG
    return max((int(w) for w, _ in re.findall(r"(\d+)x(\d+)", sizes or "")), default=0)


def est_svg(u, typ=""):
    return "svg" in typ or urllib.parse.urlparse(u).path.lower().endswith(".svg")


def candidats(base, page):
    """Icônes du site, la meilleure d'abord : (score, url)."""
    c = []
    for lien in page.links:
        rel, href = lien.get("rel", "").lower().split(), lien.get("href")
        if not href or "mask-icon" in rel:  # mask-icon = silhouette monochrome
            continue
        u = urllib.parse.urljoin(base, href)
        if "manifest" in rel:  # manifeste web : souvent du 512 px
            try:
                mu, _, m = get(u)
                for i in json.loads(m).get("icons", []):
                    if "monochrome" in i.get("purpose", "") or not i.get("src"):
                        continue
                    iu = urllib.parse.urljoin(mu, i["src"])
                    t = SVG if est_svg(iu, i.get("type", "")) else taille(i.get("sizes"))
                    c.append((t - ("maskable" in i.get("purpose", "")), iu))
            except Exception:
                pass
        elif "icon" in rel or any(r.startswith("apple-touch-icon") for r in rel):
            t = SVG if est_svg(u, lien.get("type", "")) else taille(lien.get("sizes"))
            if not t:
                t = 180 if "icon" not in rel else 32
            c.append((t, u))
    c.sort(key=lambda x: -x[0])
    c.append((16, urllib.parse.urljoin(base, "/favicon.ico")))
    # Dernier recours : service de favicons Google (sites publics seulement)
    hote = urllib.parse.urlparse(base).hostname or ""
    if "." in hote and not hote.endswith((".lan", ".local", ".home", ".internal")):
        c.append((0, f"https://www.google.com/s2/favicons?domain={hote}&sz=256"))
    return c


def enregistrer(u, dest):
    _, typ, data = get(u)
    if est_svg(u, typ) and b"<svg" in data[:4000]:
        with open(dest + ".svg", "wb") as f:
            f.write(data)
        return dest + ".svg"
    im = Image.open(io.BytesIO(data))  # ICO : Pillow ouvre la plus grande taille
    im = im.convert("RGBA")
    if im.width < 16:
        raise ValueError("icône trop petite")
    im.thumbnail((256, 256), Image.LANCZOS)
    im.save(dest + ".png")
    return dest + ".png"


def nom_suggere(page, base):
    for cle in ("application-name", "og:site_name", "apple-mobile-web-app-title"):
        if page.meta.get(cle):
            return page.meta[cle]
    titre = re.split(r"\s+[-|–—·:]\s+", page.titre.strip())[0].strip()
    return titre or (urllib.parse.urlparse(base).hostname or "").removeprefix("www.")


def fetch(url, dest):
    page = Page()
    try:
        base, _, html = get(url, 2_000_000)
        page.feed(html.decode("utf-8", "replace"))
    except OSError as e:  # page bloquée (anti-bot…) : on tente quand même favicon.ico / Google
        print(f"page illisible ({e}), repli sur favicon.ico", file=sys.stderr)
        base = url
    for _, u in candidats(base, page):
        try:
            print(enregistrer(u, dest))
            break
        except Exception:
            continue
    else:
        sys.exit("aucune icône exploitable trouvée")
    print(nom_suggere(page, base))


def slug(nom):
    s = unicodedata.normalize("NFKD", nom).encode("ascii", "ignore").decode().lower()
    print(re.sub(r"[^a-z0-9]+", "-", s).strip("-") or "app")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "fetch":
        fetch(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "slug":
        slug(sys.argv[2])
    else:
        sys.exit(__doc__)
