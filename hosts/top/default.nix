{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../sys
    ../../modules/sys/dsk/plasma.nix
    ../../modules/sys/dsk/hyprland.nix
    ../../modules/sys/gme/steam.nix
    ../../modules/sys/hw/nvidia.nix
  ];

  environment.systemPackages = with pkgs; [
    koboldcpp-latest
    ollama-latest-cuda
    diffusion-pipe-env
    setup-diffusion-pipe
  ];

  networking.hostName = "top";
  networking.firewall = {
    allowedUDPPorts = [ 38899 ];
    allowedTCPPorts = [ 38899 8188 ];
    #allowedTCPPorts = [ 8188 ]; 
 };

  swapDevices = [{
    device = "/var/lib/swapfile";
    size = 16*1024; # 16 GB
  }];

  services = {
    udisks2.enable = true;
    printing.enable = true;
    pulseaudio.enable = false;
    flatpak.enable = true;
    pipewire = {
      enable = true;
      alsa = { enable = true; support32Bit = true; };
      pulse.enable = true;
    };
    hardware.openrgb.enable = true;
  };

  security.rtkit.enable = true;
  # LETS TRY TO FIX THE FUCKING AUDIO IN ABLETON
  powerManagement.cpuFreqGovernor = "performance";
  #services.pipewire.extraConfig.pipewire."92-low-latency" = {
 # 	"context.properties" = {
 #   		"default.clock.rate" = 48000;
 #   		"default.clock.allowed-rates" = [ 48000 ];
		#"default.clock.quantum" = 1024;
    		#"default.clock.min-quantum" = 1024;
  #  	"default.clock.max-quantum" = 1024;
 # 	};
 # };
  #boot.kernelParams = [ "split_lock_detect=off" ]; 
 
  virtualisation.vmware.host.enable = true;

  programs.kdeconnect.enable = true;

  fonts = {
    packages = with pkgs; [
      noto-fonts-cjk-sans
    ];
    enableDefaultPackages = true;
    fontconfig.enable = true;
    fontDir.enable = true;
  };
}
