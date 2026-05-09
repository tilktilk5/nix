{ pkgs, ... }:

{
  home.packages = with pkgs; [
    vim
    btop
    tree
    unzip
    git
    nh
    wget
    curl
    rsync
    htop
    fastfetch
    broot
    cmatrix
    croc
    libnotify
    home-manager
    killall
    lutris
    kitty
  ];
}
