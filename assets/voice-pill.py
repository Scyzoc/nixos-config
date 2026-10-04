#!/usr/bin/env python3
# Pilule d'enregistrement vocal (style iMessage) : cercle REC + waveform + timer.
# Barres alimentées par cava (sortie raw ascii sur stdout).
import gi, os, time, subprocess, tempfile, math
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, GtkLayerShell, GLib, Gdk

NBARS = 20
W, H = 280, 54

CAVA_CONF = """[general]
framerate = 60
bars = {n}
[input]
method = pulse
source = default
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
[smoothing]
noise_reduction = 30
""".format(n=NBARS)


class Pill(Gtk.Window):
    def __init__(self):
        super().__init__()
        self.bars = [0.0] * NBARS
        self.start = time.time()

        # --- layer-shell : overlay flottant, sans focus, en bas centré ---
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, 70)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)

        # fond transparent (la pilule est dessinée au cairo)
        self.set_app_paintable(True)
        screen = self.get_screen()
        vis = screen.get_rgba_visual()
        if vis:
            self.set_visual(vis)

        self.area = Gtk.DrawingArea()
        self.area.set_size_request(W, H)
        self.area.connect("draw", self.on_draw)
        self.add(self.area)

        self.start_cava()
        GLib.timeout_add(100, self.tick)
        self.connect("destroy", lambda *_: Gtk.main_quit())

    # ---- cava : lit les valeurs de barres en continu ----
    def start_cava(self):
        f = tempfile.NamedTemporaryFile("w", suffix=".conf", delete=False)
        f.write(CAVA_CONF)
        f.close()
        self.conf = f.name
        self.proc = subprocess.Popen(
            ["cava", "-p", self.conf],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=1, text=True,
        )
        GLib.io_add_watch(self.proc.stdout, GLib.IO_IN, self.on_cava)

    def on_cava(self, src, cond):
        line = src.readline()
        if not line:
            return True
        try:
            vals = [int(x) for x in line.strip().rstrip(";").split(";") if x != ""]
            if vals:
                self.bars = [min(1.0, v / 100.0) for v in vals[:NBARS]]
        except ValueError:
            pass
        self.area.queue_draw()
        return True

    def tick(self):
        self.area.queue_draw()
        return True

    # ---- dessin ----
    def on_draw(self, area, cr):
        w = area.get_allocated_width()
        h = area.get_allocated_height()

        # fond transparent
        cr.set_operator(1)  # CAIRO_OPERATOR_SOURCE -> clear via alpha 0
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(2)  # OVER

        # --- pilule blanche arrondie + bordure ---
        pad = 1.5
        r = (h - 2 * pad) / 2
        self.rounded(cr, pad, pad, w - 2 * pad, h - 2 * pad, r)
        cr.set_source_rgba(1, 1, 1, 0.98)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.10)
        cr.set_line_width(1)
        cr.stroke()

        # --- cercle REC noir (gauche) ---
        cr.set_source_rgb(0.10, 0.10, 0.11)
        cy = h / 2
        cx = 18
        crad = 11
        cr.arc(cx, cy, crad, 0, 2 * math.pi)
        cr.fill()

        # --- timer (droite) ---
        el = int(time.time() - self.start)
        txt = "%02d:%02d" % (el // 60, el % 60)
        cr.select_font_face("monospace", 0, 0)
        cr.set_font_size(14)
        ext = cr.text_extents(txt)
        tx = w - 16 - ext.width
        cr.set_source_rgba(0.45, 0.45, 0.47, 1)
        cr.move_to(tx, cy + ext.height / 2)
        cr.show_text(txt)

        # --- waveform (centre) ---
        x0 = cx + crad + 12
        x1 = tx - 12
        region = x1 - x0
        bw = 3.0
        n = NBARS
        gap = (region - n * bw) / (n - 1)
        maxh = h * 0.55
        cr.set_source_rgba(0.13, 0.13, 0.15, 1)
        for i, v in enumerate(self.bars):
            bx = x0 + i * (bw + gap)
            bh = max(3, v * maxh)
            self.rounded(cr, bx, cy - bh / 2, bw, bh, bw / 2)
            cr.fill()

    def rounded(self, cr, x, y, w, h, r):
        r = min(r, w / 2, h / 2)
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def cleanup(self):
        try:
            self.proc.terminate()
        except Exception:
            pass
        try:
            os.unlink(self.conf)
        except Exception:
            pass


if __name__ == "__main__":
    win = Pill()
    win.show_all()
    try:
        Gtk.main()
    finally:
        win.cleanup()
