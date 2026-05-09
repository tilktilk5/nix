{ pkgs, inputs, ... }:

let
  diffusion-pipe-env = pkgs.buildFHSEnv {
    name = "diffusion-pipe";
    targetPkgs = pkgs: with pkgs; [
      python312
      python312Packages.pip
      python312Packages.virtualenv
      cudaPackages.cudatoolkit
      cudaPackages.cudnn
      cudaPackages.cuda_nvcc
      cudaPackages.libcublas
      git
      gitRepo
      gnutar
      gzip
      libGL
      libGLU
      libx11
      libxext
      libxrender
      libice
      libsm
      glib
      zlib
      stdenv.cc.cc.lib
      binutils
      gnumake
      cmake
      pkg-config
      ninja
      which
      ffmpeg
    ];
    runScript = "bash";
    profile = ''
      export CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}
      export LD_LIBRARY_PATH=/run/opengl-driver/lib:/run/opengl-driver-32/lib:${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH
      export EXTRA_LDFLAGS="-L/lib -L${pkgs.linuxPackages.nvidia_x11}/lib"
      export EXTRA_CCFLAGS="-I/usr/include"
    '';
  };

  setup-diffusion-pipe = pkgs.writeShellScriptBin "setup-diffusion-pipe" ''
    if [ -d "diffusion-pipe" ]; then
      echo "Directory diffusion-pipe already exists."
    else
      echo "Copying diffusion-pipe source from Nix store..."
      # diffusion-pipe input is a path
      cp -r ${inputs.diffusion-pipe} diffusion-pipe
      chmod -R +w diffusion-pipe
      echo "Done. Now 'cd diffusion-pipe' and run 'diffusion-pipe' to enter the environment."
    fi
  '';

  koboldcpp-latest = pkgs.koboldcpp.overrideAttrs (oldAttrs: rec {
    version = "1.109.2";
    src = pkgs.fetchFromGitHub {
      owner = "LostRuins";
      repo = "koboldcpp";
      rev = "v${version}";
      hash = "sha256-ZbhDFhsIcz+hJs8aX/XjpeH5BLGxYgaWgKPSNclb6FI=";
    };
  });

  ollama-go125-cuda = pkgs.ollama-cuda.override {
    buildGoModule = pkgs.buildGo125Module;
  };

  ollama-latest-cuda = ollama-go125-cuda.overrideAttrs (oldAttrs: rec {
    version = "git";
    src = inputs.ollama-src;
    vendorHash = "sha256-Lc1Ktdqtv2VhJQssk8K1UOimeEjVNvDWePE9WkamCos=";
    doCheck = false;
  });
in
{
  inherit diffusion-pipe-env setup-diffusion-pipe koboldcpp-latest ollama-latest-cuda;
}
