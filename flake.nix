{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ollama-src = {
      url = "github:ollama/ollama";
      flake = false;
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    diffusion-pipe = {
      url = "git+https://github.com/tdrussell/diffusion-pipe?submodules=1";
      flake = false;
    };
  };

  outputs = { nixpkgs, home-manager, plasma-manager, ... }@inputs:
    let
      user = "lam";
      
      # Helper for NixOS configurations
      mkSystem = host: system: 
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs user host; };
          modules = [
            ./hosts/${host}
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = { inherit inputs user host; };
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "backup";
                sharedModules = [ plasma-manager.homeModules.plasma-manager ];
                users.${user} = import ./lam.nix;
              };
            }
            # Add custom packages as an overlay or similar if needed, 
            # but for now we'll pass them via specialArgs or just let the host import them.
            ({ pkgs, ... }: {
              nixpkgs.overlays = [
                (final: prev: (import ./pkgs/custom.nix { pkgs = final; inherit inputs; }))
              ];
            })
          ];
        };
    in
    {
      nixosConfigurations = {
        top = mkSystem "top" "x86_64-linux";
        blet = mkSystem "blet" "x86_64-linux";
      };

      # Keep the standalone homeConfigurations if still needed
      homeConfigurations = {
        "${user}" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; };
          extraSpecialArgs = { inherit inputs user; };
          modules = [
            ./lam.nix
            plasma-manager.homeModules.plasma-manager
          ];
        };
      };

      devShells.x86_64-linux.diffusion-pipe = 
        let 
          pkgs = import nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; };
          custom = import ./pkgs/custom.nix { inherit pkgs inputs; };
        in 
        custom.diffusion-pipe-env.env;
    };
}
