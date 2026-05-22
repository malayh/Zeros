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
    impala
    bluetui
    util-linux  # rfkill lives here

    # power / brightness
    power-profiles-daemon
    brightnessctl
    ddcutil

    # apps
    ghostty
    kdePackages.dolphin

    # Qt / GTK theming
    nwg-look
    kdePackages.qt6ct
    libsForQt5.qt5ct
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
