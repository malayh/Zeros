{ config, pkgs, ... }:
{
    home.username = "malay";
    home.homeDirectory = "/home/malay";
    home.stateVersion = "25.11";
    programs.bash = {
        enable = true;
        profile
        profileExtra = ''
            exec hyprland
        '';
    }
    home.file."./config/hypr".source = "./config/hypr";
    home.file."./config/waybar".source = "./config/hypr";
}