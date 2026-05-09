{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../sys
    ../../modules/sys/dsk/plasma.nix
    ../../modules/sys/dsk/hyprland.nix
  ];

  networking.hostName = "blet";

  # 2-in-1 specific
  hardware.sensor.iio.enable = true;
  
  # Power management
  services.tlp.enable = true;
  
  # Touchpad support
  services.libinput.enable = true;

  # Printing
  services.printing.enable = true;

  # Audio
  services.pipewire = {
    enable = true;
    alsa = { enable = true; support32Bit = true; };
    pulse.enable = true;
  };
  
  security.rtkit.enable = true;
}
