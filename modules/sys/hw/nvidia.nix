{ config, pkgs, ... }:

{
  hardware = {
    graphics = { enable = true; enable32Bit = true; };
    nvidia = {
      modesetting.enable = true;
      open = true;
      nvidiaSettings = true;
      powerManagement.enable = false;
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  environment.sessionVariables = {
    QTWEBENGINE_FORCE_USE_GBM = "0";
  };
}
