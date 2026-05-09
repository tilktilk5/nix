{ pkgs, ... }:

{
  home.packages = with pkgs; [
    kdePackages.kdeconnect-kde
    kdePackages.kcolorchooser
    kdePackages.kate
    kdePackages.kdenlive
    kdePackages.qttools
    kdePackages.elisa
    kdePackages.qtsvg
    kdePackages.breeze
    kdePackages.qtstyleplugin-kvantum
    kdePackages.plasmatube
    kdePackages.kcalc
    ];
}
