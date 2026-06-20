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
          armPkgs = import nixpkgs { inherit system; crossSystem = { system = "armv7l-linux"; }; };
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
            sed -i 's/SWIG_Python_AppendOutput/SWIG_AppendOutput/g' scripts/dtc/pylibfdt/libfdt.i_shipped
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
              usbutils
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
              
              # Set up a clean staging workspace inside your current repository block
              mkdir -p ./images
              
              UBOOT_SRC="${uboot-chip}/u-boot-sunxi-with-spl.bin"
              
              if [ -f "$UBOOT_SRC" ]; then
                # 1. Carve out the first 32KB block for the secondary program loader (SPL)
                dd if="$UBOOT_SRC" of=./images/sunxi-spl.bin bs=1k count=32 status=none
                
                # 2. Carve out the remaining payload layout for the final U-Boot image
                dd if="$UBOOT_SRC" of=./images/u-boot-dtb.bin bs=1k skip=32 status=none
                
                echo "✅ Automatically sliced and staged U-Boot binaries inside ./images/!"
              else
                echo "❌ Error: Compiled U-Boot asset source not found in Nix store."
              fi

              echo "✅ Flashing and file system tools (mtdutils) are ready in your PATH!"
              echo ""
              echo "👉 Staging checklist layout:"
              echo "   ./images/sunxi-spl.bin  (Generated)"
              echo "   ./images/u-boot-dtb.bin (Generated)"
              echo "   ./images/rootfs.ubi     (Awaiting your build)"
              echo "========================================================="
            '';
          };
      });
}
