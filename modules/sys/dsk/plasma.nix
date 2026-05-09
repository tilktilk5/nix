{ config, pkgs, ... }:

{
  services = {
    displayManager.sddm.enable = true;
    desktopManager.plasma6.enable = true;
    displayManager.defaultSession = "plasma";
  };

  # programs.aeroshell = {
  #   enable = true;
  #   fonts.enable = false;
  #   polkit.enable = true;
  #   aerothemeplasma = {
  #     enable = true;
  #     sddm.enable = true;
  #     plymouth.enable = false;
  #   };
  # };
}
