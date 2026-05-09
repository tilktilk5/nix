{ pkgs, ... }:

{
  home.packages = with pkgs; [
    hyprland
    hyprlauncher
    hyprsunset
    hyprpaper
    hyprlang
    swaybg
    waybar
    networkmanagerapplet
    brightnessctl
    ddcutil
    pamixer
    ly
    labwc
    quickshell
    noctalia-shell
    ];
}
