{ config, pkgs, ... }:

{
  # programs.slskd = {
    #enable = true;
    home.file.".local/share/slskd/slskd.yml".text = ''
    web:
      authentication:
        api_keys:
          soul_sync:
            key: "4a6f881f68bc1532e6530bfab955efb6"
            role: Administrator
  '';
}
