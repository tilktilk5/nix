{ pkgs, ... }:

{
  home.packages = with pkgs; [
    cascadia-code
    source-code-pro
    mononoki
    vista-fonts
    noto-fonts-color-emoji
  ];
}
