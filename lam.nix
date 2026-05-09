{ config, pkgs, inputs, user, host, ... }:

{
  imports = [
    ./home
  ] ++ (if host == "top" then [ ./modules/home/plasma.nix ] else []);

  home = {
    username = "${user}";
    homeDirectory = "/home/${user}";
    stateVersion = "25.11";
    enableNixpkgsReleaseCheck = false;
  };
}
