{ config, pkgs, ... }:
{
  home.username      = "malay";
  home.homeDirectory = "/home/malay";
  home.stateVersion  = "25.11";

  # ~/.config/scripts on PATH so the custom-* helpers are findable.
  home.sessionPath = [ "$HOME/.config/scripts" ];

  home.sessionVariables = {
    TERMINAL = "ghostty";
    EDITOR   = "vim";
    XCOMPOSEFILE = "$HOME/.XCompose";
  };

  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name    = "Bibata-Modern-Ice";
    size    = 24;
    gtk.enable = true;
  };

  home.packages = with pkgs; [
    # hyprland ecosystem
    hyprlock
    hypridle
    hyprpicker
    hyprpaper
    swaybg

    # bar / notifications / launchers
    waybar
    swaynotificationcenter
    rofi
    wofi

    # clipboard + screenshot pipeline
    wl-clipboard
    cliphist
    wtype
    grim
    slurp
    satty
    wayfreeze
    imagemagick

    # audio / network / bt TUIs
    pamixer
    wiremix
    bluetui
    util-linux  # rfkill lives here

    # power / brightness
    power-profiles-daemon
    brightnessctl
    ddcutil

    # apps
    ghostty
    nautilus
    gnome-boxes
    libreoffice
    chromium
    brave
    obsidian
    localsend
    qbittorrent
    vlc
    just
    zoxide

    # GTK / Qt theme config GUIs.  Themes are NOT installed declaratively here —
    # use these tools (or `nix-env`/add packages later) to pick one at runtime.
    #   nwg-look          -> GTK theme/icon/cursor/font picker
    #   qt5ct / qt6ct     -> Qt5/Qt6 platform-theme picker (style + palette + icons)
    #   kvantummanager    -> Kvantum SVG-style picker (comes with qtstyleplugin-kvantum)
    nwg-look
    libsForQt5.qt5ct
    kdePackages.qt6ct
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum

    # CLI niceties carried over from the Arch list
    btop
    fzf
    jq
    unzip
    wget
    curl
    xdg-terminal-exec

    # auth / secrets client lib
    libsecret

    # removable-media auto-mount daemon (user-session side; pairs with
    # services.udisks2 in configuration.nix). Started by the systemd user unit
    # below, which UWSM hooks onto graphical-session.target.
    udiskie
  ];

  # Polkit authentication agent (replaces the Arch autostart.conf exec-once line).
  systemd.user.services.polkit-gnome = {
    Unit = {
      Description = "polkit-gnome-authentication-agent-1";
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
  };

  # USB / removable-media auto-mount. Pairs with services.udisks2 in
  # configuration.nix. graphical-session.target is raised by UWSM at session
  # start — bare Hyprland would NOT raise it, so this unit only fires under
  # the "Hyprland (UWSM)" SDDM session.
  systemd.user.services.udiskie = {
    Unit = {
      Description = "udiskie removable-media auto-mounter";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.udiskie}/bin/udiskie --automount --notify --no-tray";
      Restart = "on-failure";
    };
  };

  # Verbatim dotfile deployment: edit the files under ./config/ to change behavior.
  xdg.configFile = {
    "hypr".source    = ./config/hypr;
    "waybar".source  = ./config/waybar;
    "rofi".source    = ./config/rofi;
    "swaync".source  = ./config/swaync;
    "scripts".source = ./config/scripts;
  };

  programs.bash.enable = true;

  programs.home-manager.enable = true;
}
