{
  description = "Development environment for NextThingCo C.H.I.P. Flashing Tools";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    chip-tools-src = {
      url = "github:joelguittet/chip-tools";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, chip-tools-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = { allowUnfree = true; };
        };

        # 1. Integrated U-Boot derivation configured for cross-compilation
        uboot-chip = let 
          # Pull the armv7l-linux cross-compilation package set natively from Nixpkgs
          armPkgs = import nixpkgs { crossSystem = { system = "armv7l-linux"; }; };
        in armPkgs.stdenv.mkDerivation {
          pname = "uboot-chip";
          version = "2023.10";
          
          src = pkgs.fetchurl {
            url = "https://ftp.denx.de/pub/u-boot/u-boot-2023.10.tar.bz2";
            hash = "sha256-4A5sbwFOBGEBc50I0G8yiBHOvPWuEBNI9AnLvVXOaQA=";
          };

          nativeBuildInputs = [ 
            pkgs.buildPackages.stdenv.cc 
            pkgs.buildPackages.bison 
            pkgs.buildPackages.flex 
            pkgs.buildPackages.bc 
            pkgs.buildPackages.swig
            pkgs.buildPackages.pkg-config
            pkgs.buildPackages.openssl
            (pkgs.buildPackages.python3.withPackages (ps: [ ps.setuptools ]))
          ];

          makeFlags = [
            "HOSTCC=gcc"
            "CROSS_COMPILE=${armPkgs.stdenv.cc.targetPrefix}"
            "HOSTCFLAGS=-I${pkgs.buildPackages.openssl.dev}/include"
            "HOSTLDFLAGS=-L${pkgs.buildPackages.openssl.out}/lib"
          ];

          configurePhase = ''
            runHook preConfigure
            make CHIP_defconfig $makeFlags
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            patchShebangs tools/
            make -j$(nproc) $makeFlags
            runHook postBuild
          '';
          
          installPhase = ''
            mkdir -p $out
            cp u-boot-sunxi-with-spl.bin $out/
          '';
        };

        # 2. Existing chip-tools packaging block
        chip-tools = pkgs.stdenv.mkDerivation {
          pname = "chip-tools";
          version = "unstable";
          src = chip-tools-src;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -p $out/share/chip-tools
            cp -r * $out/share/chip-tools/
            mkdir -p $out/bin
  
            for script in $out/share/chip-tools/*.sh;
            do
              basename=$(basename "$script")
              makeWrapper "$script" "$out/bin/$basename" \
                --run "cd $out/share/chip-tools"
            done
          '';

          postFixup = ''
            patchShebangs $out/share/chip-tools/*.sh
          '';
        };
      in
      {
        # Expose both targets via 'nix build' outputs if needed
        packages = {
          default = chip-tools;
          uboot = uboot-chip;
        };

        devShells.default = assert pkgs.stdenv.hostPlatform.system != "aarch64-darwin" || builtins.throw "❌ Error: chip-tools does not support aarch64-darwin. It requires a Linux platform for raw USB flashing tooling.";
          pkgs.mkShell {
            name = "chip-tools-env";
            
            nativeBuildInputs = with pkgs; [
              git
              curl
              sunxi-tools
              android-tools
              mtdutils
              picocom
              libusb1
              pkg-config
              bashInteractive
              coreutils
              gnused
              gawk
              chip-tools
            ];

            shellHook = ''
              echo "========================================================="
              echo "  ⚡ C.H.I.P. Hardware Tools Dev Environment Loaded ⚡  "
              echo "========================================================="
              
              echo "🔨 Ensuring local U-Boot assets are built and split..."
              mkdir -p ./bin
              
              # Symlink or copy the compiled binary directly out of the Nix store
              UBOOT_SRC="${uboot-chip}/u-boot-sunxi-with-spl.bin"
              
              # Automatically split the artifacts directly into your workspace's ./bin directory
              if [ -f "$UBOOT_SRC" ]; then
                dd if="$UBOOT_SRC" of=./bin/sunxi-spl.bin bs=1k count=32 status=none
                dd if="$UBOOT_SRC" of=./bin/uboot.bin bs=1k skip=32 status=none
                echo "✅ Staged U-Boot binaries successfully in ./bin/!"
              else
                echo "❌ Error: Compiled U-Boot asset not found in Nix store."
              fi

              echo "✅ Flashing scripts are cleanly patched and ready in your PATH!"
              echo ""
              echo "👉 Run them directly from anywhere:"
              echo "   chip-flash-chip.sh"
              echo "   chip-flash-chip-pro.sh"
              echo ""
              echo "👉 To interface with your hardware over serial:"
              echo "   picocom -b 115200 /dev/ttyUSB0"
              echo "========================================================="
            '';
          };
      });
}
