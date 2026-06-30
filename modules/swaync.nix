{ config, pkgs, ... }:

{
  # ==========================================================================
  # CONFIG SWAYNC (notifications)
  # ==========================================================================
  xdg.configFile."swaync/config.json".text = ''
    {
      "positionX": "right",
      "positionY": "top",
      "layer": "overlay",
      "control-center-layer": "top",
      "layer-shell": true,
      "cssPriority": "user",
      "control-center-margin-top": 10,
      "control-center-margin-bottom": 10,
      "control-center-margin-right": 10,
      "control-center-margin-left": 10,
      "notification-2fa-action": true,
      "notification-inline-replies": true,
      "notification-icon-size": 48,
      "notification-body-image-height": 160,
      "notification-body-image-width": 200,
      "timeout": 8,
      "timeout-low": 4,
      "timeout-critical": 0,
      "fit-to-screen": false,
      "control-center-width": 400,
      "control-center-height": 600,
      "notification-window-width": 380,
      "keyboard-shortcuts": true,
      "image-visibility": "when-available",
      "transition-time": 200,
      "hide-on-clear": false,
      "hide-on-action": true,
      "script-fail-notify": true,
      "widgets": ["title", "dnd", "notifications"],
      "widget-config": {
        "title": {
          "text": "Notifications",
          "clear-all-button": true,
          "button-text": "Tout effacer"
        },
        "dnd": {
          "text": "Ne pas deranger"
        },
        "notifications": {
          "group-by": "app-name",
          "show-actions": true
        }
      }
    }
  '';

  # ==========================================================================
  # STYLE SWAYNC (notifications)
  # ==========================================================================
  xdg.configFile."swaync/style.css".text = ''
    * {
      font-family: "JetBrainsMono Nerd Font";
      transition: all 0.3s ease;
    }

    .notification-row {
      outline: none;
      margin: 4px 0px;
    }

    .notification {
      background-color: rgba(0, 0, 0, 0.25); /* Fond sombre translucide */
      border: 1px solid rgba(255, 255, 255, 0.1);
      /* border-radius: 15px; */
      /* padding: 10px; */
      /* box-shadow: 0 4px 15px rgba(0, 0, 0, 0.3); */
    }

    .notification:hover {
      background-color: rgba(128, 128, 128, 0.2); /* Léger fond gris au survol */
      border-color: rgba(255, 255, 255, 0.5);
      box-shadow: 0 0 10px 2px rgba(255, 255, 255, 0.3); /* Lueur blanche externe */
    }

    .notification-content {
      margin: 4px;
    }

    .summary {
      font-size: 14px;
      font-weight: bold;
      color: #ffffff;
      margin-bottom: 2px;
      text-shadow: 0px 0px 5px rgba(0, 0, 0, 0.8), 0px 0px 2px rgba(0, 0, 0, 1);
    }

    .body {
      font-size: 13px;
      color: #bac2de;
      text-shadow: 0px 0px 5px rgba(0, 0, 0, 0.8), 0px 0px 2px rgba(0, 0, 0, 1);
    }

    .notification-default-action,
    .notification-action {
      background-color: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.05);
      border-radius: 8px;
      color: #cdd6f4;
      padding: 8px;
      margin: 4px;
    }

    .notification-action:hover {
      background-color: rgba(255, 255, 255, 0.1);
      border-color: rgba(137, 180, 250, 0.5);
    }

    /* BOUTON DE FERMETURE AVEC CROIX */
    .close-button {
      background-color: rgba(255, 255, 255, 0.1);
      border-radius: 50%;
      margin: 8px;
      min-width: 24px;
      min-height: 24px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      transition: all 0.2s ease;
      
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'%3E%3Cline x1='18' y1='6' x2='6' y2='18'%3E%3C/line%3E%3Cline x1='6' y1='6' x2='18' y2='18'%3E%3C/line%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: center;
      background-size: 14px;
    }

    .close-button:hover {
      background-color: #f38ba8;
      border-color: #f38ba8;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'%3E%3Cline x1='18' y1='6' x2='6' y2='18'%3E%3C/line%3E%3Cline x1='6' y1='6' x2='18' y2='18'%3E%3C/line%3E%3C/svg%3E");
    }

    .close-button image,
    .close-button label {
        opacity: 0;
        min-width: 0;
        min-height: 0;
        font-size: 0;
    }

    /* CONTROL CENTER */
    .control-center {
      background-color: rgba(17, 17, 27, 0.8);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 15px;
      margin: 10px;
      padding: 10px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
    }

    .widget-title {
      color: #cba6f7;
      font-size: 18px;
      margin: 10px;
    }

    .widget-title button {
      background-color: rgba(243, 139, 168, 0.15);
      color: #f38ba8;
      border-radius: 8px;
      padding: 4px 12px;
      font-size: 12px;
    }

    .widget-title button:hover {
      background-color: rgba(243, 139, 168, 0.3);
    }

    .widget-dnd {
      margin: 10px;
      font-size: 14px;
      color: #bac2de;
    }

    .widget-dnd switch {
      background-color: rgba(255, 255, 255, 0.05);
      border-radius: 12px;
      border: 1px solid rgba(255, 255, 255, 0.1);
    }

    .widget-dnd switch slider {
      background-color: #89b4fa;
      border-radius: 12px;
    }

    .notification-group-header {
      font-size: 12px;
      color: #89b4fa;
      padding: 8px;
      font-weight: bold;
      text-transform: uppercase;
    }

    .blank-window {
      background-color: transparent;
    }

    /* URGENCES — colorisation de la bordure gauche */
    .notification.low {
      border-left: 3px solid #a6e3a1; /* vert — succès / info */
    }

    .notification.normal {
      border-left: 3px solid #f9e2af; /* jaune — avertissement */
    }

    .notification.critical {
      border-left: 3px solid #f38ba8; /* rouge — erreur critique */
      animation: blink 1s step-start 3;
    }

    @keyframes blink {
      50% { opacity: 0.4; }
    }
  '';
}