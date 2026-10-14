{ config, pkgs, lib, ... }:

# Config Hyprland en Lua (le format .conf disparaît en 0.57).
# Générée dans ~/.config/hypr/hyprland.lua par home-manager (configType = "lua").
#
# ⚠ En Lua, `hyprctl keyword` et `hyprctl dispatch <ancienne syntaxe>` ne marchent plus :
#   - réglages à chaud  → hyprctl eval 'hl.config({ ... })' / hl.monitor / hl.workspace_rule
#   - dispatchers       → hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })'
#   - Quickshell        → Hyprland.dispatch("hl.dsp.exec_cmd(...)") (expression Lua)
let
  azertyKeys = ''{ "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft", "minus", "egrave", "underscore", "ccedilla", "agrave" }'';
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    settings = { };
    extraConfig = ''
      local mod = "SUPER"
      local terminal = "kitty"
      local menu = "app-launcher"
      local home = os.getenv("HOME")

      -- Environnement
      hl.env("XDG_SESSION_TYPE", "wayland")
      hl.env("XCURSOR_SIZE", "24")
      hl.env("HYPRCURSOR_SIZE", "24")
      hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
      -- Contourne un crash Aquamarine/AMD (SDRMConnector::releaseCommitBuffers, SIGABRT)
      -- au branchement d'un écran externe : désactive l'atomic modesetting DRM.
      hl.env("AQ_NO_ATOMIC", "1")

      -- Écrans
      hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "1520x1440", scale = 1 })
      hl.monitor({ output = "desc:Xiaomi Corporation Mi monitor 5505610117971", mode = "3440x1440@120", position = "0x0", scale = 1 })
      hl.monitor({ output = "desc:Microstep MSI MAG241C 0x00000010", mode = "1920x1080@144", position = "3440x0", scale = 1, transform = 3 })
      hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

      -- Chargés en dernier pour que leurs règles priment sur les défauts ci-dessus :
      --  monitors.lua   : écrit par nwg-displays (bouton Apply)
      --  workspaces.lua : écrit par workspace-bind (modules/display-switch.nix), un bloc
      --                   de 10 workspaces par écran actif ou les groupes de display-layouts
      for _, f in ipairs({ "monitors.lua", "workspaces.lua" }) do
        pcall(dofile, home .. "/.config/hypr/" .. f)
      end

      -- Démarrage
      hl.on("hyprland.start", function()
        for _, cmd in ipairs({
          "systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland",
          "hyprctl setcursor Bibata-Modern-Ice 24",
          "xhost +si:localuser:root",
          "swaync",
          "awww-daemon",
          "awww restore || true",
          "wl-paste --type text --watch cliphist store",
          "wl-paste --type image --watch cliphist store",
          "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1",
          -- --no-agent : la barre Quickshell gère les mots de passe Wi-Fi ; sinon NM
          -- attend la fenêtre de nm-applet avant d'abandonner (demande de mdp très lente)
          "nm-applet --indicator --no-agent",
          "workspace-bind",
        }) do
          hl.exec_cmd(cmd)
        end
      end)

      -- Entrées
      hl.config({
        input = {
          kb_layout = "fr",
          kb_variant = "azerty",
          numlock_by_default = true,
          follow_mouse = 1,
          touchpad = { natural_scroll = true, tap_to_click = true, drag_lock = true },
        },
        cursor = { inactive_timeout = 2, no_hardware_cursors = true },
      })
      hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

      -- Apparence
      hl.config({
        general = {
          gaps_in = 5,
          -- = marges gauche/droite de la barre Quickshell (Bar.qml) → bords alignés
          gaps_out = 10,
          border_size = 1,
          col = { active_border = "rgba(ffffffff)", inactive_border = "rgba(595959aa)" },
          resize_on_border = false,
          allow_tearing = false,
          layout = "dwindle",
        },
        decoration = {
          rounding = 10,
          active_opacity = 1.0,
          inactive_opacity = 1.0,
          shadow = { enabled = true, range = 4, render_power = 3, color = "rgba(1a1a1aee)" },
          blur = { enabled = true, size = 4, passes = 1, ignore_opacity = false, new_optimizations = true },
        },
        animations = { enabled = true },
        -- disable_autoreload : workspace-bind réécrit workspaces.lua (chargé par dofile) ;
        -- l'autoreload rechargeait alors toute la config et effaçait les règles
        -- posées à chaud (mode miroir annulé au bout de 2 s). Le rebuild
        -- home-manager fait déjà `hyprctl reload` lui-même.
        misc = { force_default_wallpaper = 0, disable_hyprland_logo = true, vrr = 2, disable_autoreload = true },
        render = { direct_scanout = false },
        dwindle = { preserve_split = true },
      })

      local function curve(name, x1, y1, x2, y2)
        hl.curve(name, { type = "bezier", points = { { x1, y1 }, { x2, y2 } } })
      end
      curve("easeOutQuint", 0.23, 1, 0.32, 1)
      curve("linear", 0, 0, 1, 1)
      curve("snap", 0.19, 1, 0.22, 1)
      curve("smoothOut", 0.36, 0, 0.66, -0.56)
      curve("smoothIn", 0.25, 1, 0.5, 1)

      local function anim(leaf, speed, bezier, style)
        hl.animation({ leaf = leaf, enabled = true, speed = speed, bezier = bezier, style = style })
      end
      anim("global", 3, "snap")
      anim("border", 3, "easeOutQuint")
      anim("windows", 2, "snap")
      anim("windowsIn", 2, "snap", "popin 87%")
      anim("windowsOut", 2, "easeOutQuint", "popin 87%")
      anim("fadeIn", 2, "linear")
      anim("fadeOut", 2, "linear")
      anim("fade", 2, "linear")
      anim("layers", 2, "snap")
      anim("layersIn", 2, "snap", "fade")
      anim("layersOut", 2, "easeOutQuint", "fade")
      anim("fadeLayersIn", 2, "linear")
      anim("fadeLayersOut", 2, "linear")
      anim("workspaces", 3, "smoothIn", "slide")
      anim("workspacesIn", 3, "smoothIn", "slide")
      anim("workspacesOut", 3, "smoothOut", "slide")
      -- Scratchpad : fondu seul, le zoom des fenêtres est fait par special-zoom
      anim("specialWorkspace", 2, "snap", "fade")
      anim("specialWorkspaceOut", 2, "linear", "fade")

      -- Raccourcis
      local function run(keys, cmd, opts)
        hl.bind(keys, hl.dsp.exec_cmd(cmd), opts)
      end

      run(mod .. " + C", terminal)
      run(mod .. " + B", "brave")
      run(mod .. " + G", "brave --app=https://gemini.google.com")
      run(mod .. " + A", "brave --app=https://claude.ai/new")
      run(mod .. " + N", "brave --app=https://www.notion.so/ID_CENSURE")
      run(mod .. " + ALT + P", "brave --app=https://calendar.notion.so/")
      run(mod .. " + Y", "brave --app=https://www.youtube.com/")
      run(mod .. " + S", "spotify")
      run(mod .. " + T", "brave --app=https://atlas.homelab.lan")
      run(mod .. " + D", "discord-launcher")
      run(mod .. " + R", menu)
      run(mod .. " + E", "thunar")
      run(mod .. " + W", "wallpaper-picker")
      run(mod .. " + V", "clipboard-manager")
      run(mod .. " + L", "hyprlock")
      run(mod .. " + semicolon", "emoji-picker")
      run(mod .. " + I", "kitty --class internet-check -e internet-check")
      run(mod .. " + U", terminal .. " --class nmtui -e nmtui")
      run(mod .. " + ALT + S", "audio-switch")
      run(mod .. " + O", "obsidian 'obsidian://open?vault=Obsidian'")
      run(mod .. " + SHIFT + O", "pwvucontrol")
      run(mod .. " + SHIFT + V", "voice-to-text")
      run(mod .. " + SHIFT + N", "notion-todo")
      -- Scratchpad : fondu + zoom depuis le centre (modules/special-zoom.nix) — X car S est pris par Spotify
      run(mod .. " + X", "special-zoom magic")
      run(mod .. " + Tab", "ws-cycle next")
      run(mod .. " + SHIFT + Tab", "ws-cycle prev")
      run(mod .. " + CTRL + Tab", "ws-compact")
      run("Print", "screenshot copy")
      run("SHIFT + Print", "screenshot save")

      hl.bind(mod .. " + Q", hl.dsp.window.close())
      hl.bind(mod .. " + SHIFT + M", hl.dsp.exit())
      hl.bind(mod .. " + Space", hl.dsp.window.float({ action = "toggle" }))
      hl.bind(mod .. " + J", hl.dsp.layout("togglesplit"))
      hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
      hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
      hl.bind(mod .. " + SHIFT + X", hl.dsp.window.move({ workspace = "special:magic" }))

      for key, dir in pairs({ left = "left", right = "right", up = "up", down = "down" }) do
        hl.bind(mod .. " + " .. key, hl.dsp.focus({ direction = dir }))
        hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
      end

      hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
      hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
      hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
      hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

      -- Workspaces : touches physiques sous les chiffres 1 à 0 en AZERTY
      local azerty = ${azertyKeys}
      for i, key in ipairs(azerty) do
        hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
        hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
        -- Workspaces 11 à 20 : même touche + CTRL
        hl.bind(mod .. " + CTRL + " .. key, hl.dsp.focus({ workspace = i + 10 }))
        hl.bind(mod .. " + CTRL + SHIFT + " .. key, hl.dsp.window.move({ workspace = i + 10 }))
      end

      -- Touches média
      local held = { locked = true, repeating = true }
      run("XF86AudioRaiseVolume", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0", held)
      run("XF86AudioLowerVolume", [[wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && [ "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')" = "0.00" ] && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1]], held)
      run("XF86AudioMute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", held)
      run("XF86AudioMicMute", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", held)
      run("XF86MonBrightnessUp", "brightnessctl -e4 -n2 set 5%+", held)
      run("XF86MonBrightnessDown", "brightnessctl -e4 -n2 set 5%-", held)
      run("XF86AudioNext", "playerctl next", { locked = true })
      run("XF86AudioPause", "media-tap", { locked = true })
      run("XF86AudioPlay", "media-tap", { locked = true })
      run("XF86AudioPrev", "playerctl previous", { locked = true })

      -- Règles de fenêtres
      hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })
      hl.window_rule({
        name = "fix-xwayland-drags",
        match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
        no_focus = true,
      })

      -- Fenêtre flottante centrée (terminaux d'outils, popups)
      local function popup(match, size, animated)
        local rule = { name = "popup-" .. (match.class or match.title), match = match, float = true, center = true }
        if size then rule.size = size end
        if animated then rule.animation = "popin" end
        hl.window_rule(rule)
      end
      popup({ class = "nmtui" }, "700 500")
      popup({ class = "com.saivert.pwvucontrol" }, "700 500", true)
      popup({ title = "wlogout" })
      popup({ class = "internet-check" }, "560 340", true)    -- vérification internet
      popup({ class = "netfix" }, "720 560", true)            -- netfix (menu applications)
      popup({ class = "app-uninstall" }, "760 480", true)     -- désinstallation (clic droit du menu d'applications)
      popup({ class = "notion-todo" }, nil, true)             -- menu Notion TO DO

      -- Règles de layers
      local function layer(namespace, opts)
        opts.name = "layer-" .. namespace
        opts.match = { namespace = namespace }
        hl.layer_rule(opts)
      end
      layer("quickshell-bar", { blur = true, ignore_alpha = 0.1 })
      -- Menus d'applications / presse-papiers : flou derrière le panneau seulement
      -- (pas derrière le fond assombri)
      layer("quickshell-launcher", { blur = true, ignore_alpha = 0.4 })
      layer("quickshell-clipboard", { blur = true, ignore_alpha = 0.4 })
      layer("quickshell-emoji", { blur = true, ignore_alpha = 0.4 })
      layer("swaync", { blur = true, ignore_alpha = 0.1 })
      layer("swaync-notification-window", { blur = true, ignore_alpha = 0.1 })
      layer("swaync-control-center", { blur = true, ignore_alpha = 0.1 })
      layer("launcher", { blur = true })
      layer("rofi", { blur = true, ignore_alpha = 0.1, animation = "fade" })
    '';
  };
}
