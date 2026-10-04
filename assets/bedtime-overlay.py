#!/usr/bin/env python3
# Overlay plein écran « va te coucher », calqué sur l'écran de verrouillage hyprlock :
# capture d'écran floutée (4 passes / rayon 10, luminosité 0.75, zoom 1.05),
# heure en League Spartan Bold 120 avec halo, date en League Spartan 24.
#
# Usage : bedtime-overlay.py <niveau 1-4> "<titre>" "<message>"
import sys, math, time, locale, subprocess, tempfile, os
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gtk, GtkLayerShell, GLib, Gdk, GdkPixbuf, Pango, PangoCairo

# Réglages repris tels quels de programs.hyprlock (home.nix)
BLUR_PASSES = 4
BLUR_SIZE = 10
BRIGHTNESS = 0.75
ZOOMFACTOR = 1.05
FONT_HEURE = "League Spartan Bold"
FONT_DATE = "League Spartan"
TAILLE_HEURE = 120      # px, comme hyprlock (référence écran 1080p)
TAILLE_DATE = 24
REF_H = 1080.0          # hauteur de référence pour l'échelle des polices

# Assombrissement supplémentaire et couleur d'accent par niveau d'insistance.
# Niveau 1 = rendu identique au lock screen ; ça se durcit ensuite.
NIVEAUX = {
    1: ((1.00, 1.00, 1.00), 0.00),
    2: ((0.78, 0.75, 1.00), 0.12),
    3: ((1.00, 0.65, 0.35), 0.28),
    4: ((1.00, 0.35, 0.40), 0.45),
}

# Combien de temps l'overlay reste avant de PERMETTRE la fermeture.
# Niveau 1 se ferme tout seul ; à partir de 2, il faut attendre.
ATTENTE = {1: 3, 2: 15, 3: 30, 4: 45}

# Fermeture auto (uniquement niveau 1). 0 = jamais.
AUTO_FERMETURE = {1: 12, 2: 0, 3: 0, 4: 0}

# Phrase à recopier pour fermer (niveaux 3-4). None = Échap suffit après l'attente.
PHRASE = {
    1: None,
    2: None,
    3: "je vais me coucher",
    4: "j'arrete maintenant et je vais dormir",
}


def capture_floutee():
    """Screenshot de l'écran, flouté façon hyprlock. None si grim indisponible."""
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    tmp.close()
    try:
        subprocess.run(["grim", tmp.name], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=5)
        pb = GdkPixbuf.Pixbuf.new_from_file(tmp.name)
    except Exception:
        return None
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

    # Flou approximé par aller-retour de mise à l'échelle (bilinéaire),
    # une itération par passe — même principe que le dual-kawase de hyprlock.
    w, h = pb.get_width(), pb.get_height()
    facteur = max(2, BLUR_SIZE // 2)
    pw, ph = max(1, w // facteur), max(1, h // facteur)
    for _ in range(BLUR_PASSES):
        pb = pb.scale_simple(pw, ph, GdkPixbuf.InterpType.BILINEAR)
        pb = pb.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR)
    return pb


class Overlay(Gtk.Window):
    def __init__(self, niveau, titre, message):
        super().__init__()
        self.niveau = niveau
        self.titre = titre
        self.message = message
        self.accent, self.assombri = NIVEAUX[niveau]
        self.debut = time.time()
        self.attente = ATTENTE[niveau]
        self.auto = AUTO_FERMETURE[niveau]
        self.phrase = PHRASE[niveau]
        self.saisie = ""
        self.erreur = 0.0          # timestamp du dernier caractère refusé (flash rouge)
        self.fond = capture_floutee()
        # Rectangles des boutons (x, y, w, h, action), remplis au dessin.
        self.boutons = []
        self.survol = None

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "bedtime")
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)

        self.set_app_paintable(True)
        vis = self.get_screen().get_rgba_visual()
        if vis:
            self.set_visual(vis)

        self.area = Gtk.DrawingArea()
        self.area.connect("draw", self.on_draw)
        self.add(self.area)

        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("key-press-event", self.on_key)
        # Le clic ne ferme plus rien : il faut subir l'attente.
        # Seuls les boutons « Veille » / « Éteindre » réagissent.
        self.connect("button-press-event", self.on_click)
        self.connect("motion-notify-event", self.on_motion)
        self.connect("destroy", lambda *_: Gtk.main_quit())

        GLib.timeout_add(100, self.tick)

    def restant(self):
        return max(0.0, self.attente - (time.time() - self.debut))

    # ---- boutons « Veille » / « Éteindre » ----
    def agir(self, action):
        """Suspend ou éteint la machine, puis ferme l'overlay."""
        cmd = ["systemctl", "suspend" if action == "veille" else "poweroff"]
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
        except Exception:
            pass
        Gtk.main_quit()

    def bouton_sous(self, x, y):
        for bx, by, bw, bh, action, _lib in self.boutons:
            if bx <= x <= bx + bw and by <= y <= by + bh:
                return action
        return None

    def on_click(self, _w, ev):
        action = self.bouton_sous(ev.x, ev.y)
        if action:
            self.agir(action)
        return True

    def on_motion(self, _w, ev):
        survol = self.bouton_sous(ev.x, ev.y)
        if survol != self.survol:
            self.survol = survol
            self.area.queue_draw()
        return True

    def on_key(self, _w, ev):
        libre = self.restant() <= 0

        # Raccourcis toujours actifs : obéir ne demande pas d'attendre.
        if ev.keyval == Gdk.KEY_F1:
            self.agir("veille")
            return True
        if ev.keyval == Gdk.KEY_F2:
            self.agir("eteindre")
            return True

        if self.phrase is None:
            if libre and ev.keyval in (Gdk.KEY_Escape, Gdk.KEY_Return, Gdk.KEY_space):
                Gtk.main_quit()
            return True

        # Niveaux 3-4 : recopier la phrase, caractère par caractère, sans faute.
        if ev.keyval == Gdk.KEY_BackSpace:
            self.saisie = self.saisie[:-1]
            return True

        ch = chr(Gdk.keyval_to_unicode(ev.keyval) or 0)
        if not ch or ch < " ":
            return True

        attendu = self.phrase[len(self.saisie):len(self.saisie) + 1]
        if ch.lower() == attendu.lower():
            self.saisie += attendu
        else:
            # Faute : on repart de zéro.
            self.saisie = ""
            self.erreur = time.time()

        if self.saisie == self.phrase and libre:
            Gtk.main_quit()
        return True

    def tick(self):
        if self.auto and time.time() - self.debut > self.auto:
            Gtk.main_quit()
            return False
        self.area.queue_draw()
        return True

    # ---- texte via Pango (mêmes familles que hyprlock) ----
    def texte(self, cr, txt, famille, taille, x, y, rgba, centre=True):
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription(f"{famille} {taille}"))
        layout.set_text(txt, -1)
        tw, th = layout.get_pixel_size()
        cr.move_to(x - tw / 2 if centre else x, y - th / 2)
        cr.set_source_rgba(*rgba)
        PangoCairo.show_layout(cr, layout)
        return tw, th

    def rect_arrondi(self, cr, x, y, w, h, rayon):
        cr.new_sub_path()
        cr.arc(x + w - rayon, y + rayon, rayon, -math.pi / 2, 0)
        cr.arc(x + w - rayon, y + h - rayon, rayon, 0, math.pi / 2)
        cr.arc(x + rayon, y + h - rayon, rayon, math.pi / 2, math.pi)
        cr.arc(x + rayon, y + rayon, rayon, math.pi, 1.5 * math.pi)
        cr.close_path()

    def halo(self, cr, txt, famille, taille, x, y, rgba, passes=3, rayon=15):
        """Imite shadow_passes / shadow_size / shadow_color de hyprlock."""
        for i in range(passes):
            d = rayon * (i + 1) / passes
            for dx, dy in ((-d, 0), (d, 0), (0, -d), (0, d)):
                self.texte(cr, txt, famille, taille, x + dx, y + dy,
                           (rgba[0], rgba[1], rgba[2], rgba[3] / (passes * 4)))

    def on_draw(self, area, cr):
        w = area.get_allocated_width()
        h = area.get_allocated_height()
        t = time.time() - self.debut
        ech = h / REF_H
        r, g, b = self.accent
        fade = min(1.0, t / 0.35)

        cr.set_operator(1)
        cr.set_source_rgba(0.10, 0.08, 0.08, fade)
        cr.paint()
        cr.set_operator(2)

        # --- fond : screenshot flouté, zoomé, assombri (comme hyprlock) ---
        if self.fond is not None:
            fw, fh = self.fond.get_width(), self.fond.get_height()
            ratio = max(w / fw, h / fh) * ZOOMFACTOR
            cr.save()
            cr.translate((w - fw * ratio) / 2, (h - fh * ratio) / 2)
            cr.scale(ratio, ratio)
            Gdk.cairo_set_source_pixbuf(cr, self.fond, 0, 0)
            cr.paint_with_alpha(fade)
            cr.restore()

        # brightness 0.75 + assombrissement lié au niveau
        cr.set_source_rgba(0, 0, 0, (1 - BRIGHTNESS + self.assombri) * fade)
        cr.rectangle(0, 0, w, h)
        cr.fill()

        # teinte d'accent, pulsation lente, à partir du niveau 2
        if self.niveau >= 2:
            pulse = 0.5 + 0.5 * math.sin(t * 1.5)
            cr.set_source_rgba(r, g, b, (0.05 + 0.05 * pulse) * fade)
            cr.rectangle(0, 0, w, h)
            cr.fill()

        cx = w / 2
        cy = h / 2

        # --- heure : position "0, 80" chez hyprlock (80 px au-dessus du centre) ---
        heure = time.strftime("%H:%M")
        y_heure = cy - 80 * ech
        self.halo(cr, heure, FONT_HEURE, TAILLE_HEURE * ech, cx, y_heure,
                  (1, 1, 1, 0.3 * fade))
        self.texte(cr, heure, FONT_HEURE, TAILLE_HEURE * ech, cx, y_heure,
                   (1, 1, 1, 0.9 * fade))

        # --- date : position "0, -10" ---
        try:
            locale.setlocale(locale.LC_TIME, "fr_FR.UTF-8")
        except locale.Error:
            pass
        date = time.strftime("%A %d %B").capitalize()
        self.texte(cr, date, FONT_DATE, TAILLE_DATE * ech, cx, cy + 10 * ech,
                   (1, 1, 1, 0.8 * fade))

        # --- titre du rappel ---
        self.texte(cr, self.titre, FONT_HEURE, 34 * ech, cx, cy + h * 0.14,
                   (r, g, b, 0.95 * fade))

        # --- message ---
        if self.message:
            self.texte(cr, self.message, FONT_DATE, 20 * ech, cx, cy + h * 0.20,
                       (1, 1, 1, 0.7 * fade))

        restant = self.restant()

        # --- phrase à recopier (niveaux 3-4) ---
        if self.phrase:
            y_p = cy + h * 0.29
            self.texte(cr, self.phrase, FONT_DATE, 22 * ech, cx, y_p,
                       (1, 1, 1, 0.30 * fade))
            # progression de la saisie, en surimpression sur la phrase modèle
            layout_ok = self.saisie
            rouge = time.time() - self.erreur < 0.5
            couleur = (1, 0.3, 0.3, 0.9 * fade) if rouge else (r, g, b, 0.95 * fade)
            # aligné à gauche sur la même origine que la phrase modèle
            l = PangoCairo.create_layout(cr)
            l.set_font_description(Pango.FontDescription(f"{FONT_DATE} {22 * ech}"))
            l.set_text(self.phrase, -1)
            pw_, ph_ = l.get_pixel_size()
            self.texte(cr, layout_ok, FONT_DATE, 22 * ech,
                       cx - pw_ / 2, y_p, couleur, centre=False)

        # --- boutons « Veille » / « Éteindre » ---
        # Toujours cliquables, même pendant l'attente : c'est la sortie honnête.
        bw_ = 110 * ech
        bh_ = 46 * ech
        rayon = 12 * ech
        ecart = 20 * ech
        by_ = cy + h * 0.36
        specs = [("veille", "F1  󰒲"), ("eteindre", "F2  󰐥")]
        total_w = len(specs) * bw_ + (len(specs) - 1) * ecart
        bx_ = cx - total_w / 2
        self.boutons = []
        for action, libelle in specs:
            actif = self.survol == action
            self.rect_arrondi(cr, bx_, by_, bw_, bh_, rayon)
            cr.set_source_rgba(r, g, b, (0.30 if actif else 0.15) * fade)
            cr.fill_preserve()
            cr.set_source_rgba(1, 1, 1, (0.55 if actif else 0.25) * fade)
            cr.set_line_width(1.5)
            cr.stroke()
            self.texte(cr, libelle, FONT_DATE, 17 * ech,
                       bx_ + bw_ / 2, by_ + bh_ / 2,
                       (1, 1, 1, (0.95 if actif else 0.75) * fade))
            self.boutons.append((bx_, by_, bw_, bh_, action, libelle))
            bx_ += bw_ + ecart

        # --- consigne de fermeture ---
        if restant > 0:
            consigne = f"Impossible de fermer avant {int(restant) + 1} s"
        elif self.phrase:
            consigne = "Recopie la phrase pour fermer"
        else:
            consigne = "Échap pour fermer"
        self.texte(cr, consigne, FONT_DATE, 14 * ech,
                   cx, h - h * 0.07, (1, 1, 1, 0.45 * fade))

        # --- barre : temps restant avant déblocage (ou fermeture auto niveau 1) ---
        total = self.auto if self.auto else self.attente
        prog = min(1.0, t / total) if total else 1.0
        bw = w * 0.22
        bx = (w - bw) / 2
        by = h - h * 0.045
        cr.set_source_rgba(1, 1, 1, 0.12 * fade)
        cr.rectangle(bx, by, bw, 2)
        cr.fill()
        cr.set_source_rgba(1, 1, 1, 0.5 * fade)
        cr.rectangle(bx, by, bw * (1 - prog), 2)
        cr.fill()


if __name__ == "__main__":
    niveau = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    titre = sys.argv[2] if len(sys.argv) > 2 else "Va te coucher"
    message = sys.argv[3] if len(sys.argv) > 3 else ""
    win = Overlay(max(1, min(4, niveau)), titre, message)
    win.show_all()
    Gtk.main()
