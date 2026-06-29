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
        uboot-chip = let 
          armPkgs = import nixpkgs { inherit system; crossSystem = { system = "armv7l-linux"; }; };
        in armPkgs.stdenv.mkDerivation {
          pname = "uboot-chip";
          version = "2023.10";
          src = pkgs.fetchFromGitHub {
            owner = "nextthingco";
            repo = "CHIP-u-boot";
            rev = "chip/stable";
            hash = "sha256-PwtEHtz2qbE7ir4UoOL1ySPWXUCpocZ0Eenf7o+juEg="; # Replace with actual hash after first run
          };
          nativeBuildInputs = [ 
            pkgs.buildPackages.gcc13
            pkgs.buildPackages.binutils
            pkgs.buildPackages.bison 
            pkgs.buildPackages.flex 
            pkgs.buildPackages.bc
            pkgs.buildPackages.dtc
            pkgs.buildPackages.swig
            pkgs.buildPackages.pkg-config
            pkgs.buildPackages.openssl
            (pkgs.buildPackages.python3.withPackages (ps: [ ps.setuptools ]))
          ];

          makeFlags = [
            "HOSTCC=${pkgs.buildPackages.stdenv.cc.targetPrefix}gcc"
            "CROSS_COMPILE=${armPkgs.stdenv.cc.targetPrefix}"
            "HOSTCFLAGS=-I${pkgs.buildPackages.openssl.dev}/include"
            "HOSTLDFLAGS=-L${pkgs.buildPackages.openssl.out}/lib"
            "DEVICE_TREE=sun5i-r8-chip"
            "DTC=${pkgs.buildPackages.dtc}/bin/dtc"
          ];

          postPatch = ''
            # The compiler version is detected as 13/14/15, but we only have headers up to 5.
            # We symlink/copy the highest available header (gcc5.h) to satisfy the modern compiler versions.
            cp include/linux/compiler-gcc5.h include/linux/compiler-gcc13.h
            cp include/linux/compiler-gcc5.h include/linux/compiler-gcc14.h
            cp include/linux/compiler-gcc5.h include/linux/compiler-gcc15.h
          '';

          configurePhase = ''
              ### Debug
              ls include/linux/compiler-gcc*.h

              make distclean
              make CHIP_defconfig $makeFlags
              cat >> .config <<EOF
              CONFIG_MTD=y
              CONFIG_DM_MTD=y
              CONFIG_MTD_RAW_NAND=y
              CONFIG_NAND_SUNXI=y
              CONFIG_SYS_NAND_BLOCK_SIZE=0x40000
              CONFIG_SYS_NAND_PAGE_SIZE=0x4000
              CONFIG_SYS_NAND_OOBSIZE=0x100
              CONFIG_CMD_MTD=y
              CONFIG_CMD_NAND=y
              CONFIG_CMD_UBI=y
              CONFIG_MTD_UBI=y
              CONFIG_SYS_MAX_NAND_DEVICE=1
              EOF

              ./scripts/config --enable CONFIG_USB_KEYBOARD
              ./scripts/config --enable CONFIG_USB_GADGET
              ./scripts/config --enable CONFIG_USB_STORAGE

              # Force a fail if it didn't work
              grep "CONFIG_NAND_SUNXI=y" .config || { echo "❌ CONFIG_NAND_SUNXI not set!"; exit 1; }

            make olddefconfig $makeFlags
          '';

          buildPhase = ''
            runHook preBuild
            patchShebangs tools/
            make olddefconfig $makeFlags
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
              dtc
              gcc13
              sunxi-tools
              android-tools
              usbutils
              mtdutils
              ubootTools
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
              mkdir -p ./images
              
              UBOOT_SRC="${uboot-chip}/u-boot-sunxi-with-spl.bin"
              
              if [ -f "$UBOOT_SRC" ]; then
                dd if="$UBOOT_SRC" of=./images/sunxi-spl.bin bs=1k count=32 status=none
                dd if="$UBOOT_SRC" of=./images/u-boot-dtb.bin bs=1k skip=32 status=none
                echo "✅ Automatically sliced and staged U-Boot binaries inside ./images/!"
              else
                echo "❌ Error: Compiled U-Boot asset source not found in Nix store."
              fi

              # =====================================================================
              # 📦 AUTOMATED ROOTFS PACKAGING HELPER
              # =====================================================================
              chip-pack-rootfs() {
                if [ -z "$1" ]; then
                  echo "❌ Error: Please specify the path to your rootfs tarball."
                  echo "   Usage: chip-pack-rootfs <path/to/nixos-rootfs.tar.xz>"
                  return 1
                fi

                local TARBALL="$1"
                if [ ! -f "$TARBALL" ]; then
                  echo "❌ Error: Archive file not found at: $TARBALL"
                  return 1
                fi

                echo "🧹 Making sure old workspaces are clean..."
                sudo rm -rf ./rootfs-unpack
                rm -f rootfs.ubifs ubinize.cfg

                echo "📂 Creating temporary staging folder and unpacking tarball..."
                mkdir -p ./rootfs-unpack
                
                # NOTE: Omitting explicit compression flags (-z/-J) lets modern GNU tar 
                # auto-detect whether the file is gzip or xz based on its binary magic header.
                sudo tar -C ./rootfs-unpack -xf "$TARBALL"

                echo "🏗️  Compiling intermediate UBIFS volume layer..."
                sudo mkfs.ubifs \
                  -r ./rootfs-unpack \
                  -m 16384 \
                  -e 2064384 \
                  -c 2000 \
                  -x lzo \
                  -o ./rootfs.ubifs

                echo "🧹 Removing unpack directory..."
                sudo rm -rf ./rootfs-unpack

                echo "📝 Generating container structure manifest (ubinize.cfg)..."
                cat <<EOF > ubinize.cfg
[rootfs_volume]
mode=ubi
image=rootfs.ubifs
vol_id=0
vol_type=dynamic
vol_name=rootfs
vol_flags=autoresize
EOF

                echo "🚀 Packing intermediate layout into final flashable container..."
                ubinize -o ./images/rootfs.ubi -m 16384 -p 2097152 -s 16384 ubinize.cfg

                echo "🧹 Cleaning up intermediate configuration files..."
                rm -f rootfs.ubifs ubinize.cfg

                echo "========================================================="
                echo "✅ Successfully completed! Staged artifacts:"
                ls -lh ./images
                echo "========================================================="
              }

              echo "✅ Flashing and file system tools (mtdutils) are ready in your PATH!"
              echo ""
              echo "👉 To unpack your tarball and automatically generate 'rootfs.ubi', run:"
              echo "   chip-pack-rootfs nixos-chip-*-rootfs.tar.xz"
              echo ""
              echo "👉 Once images are built, put CHIP into FTL mode, and check for usb plug in:"
              echo "   lsusb | grep -i '1f3a'"
              echo ""
              echo "👉 If you have run this build env multiple times, ensure you are using the most current u-boot sunxi:"
              echo "   sudo nix-collect-garbage"
              echo ""
              echo "👉 Once in FTL mode, run the flash script:"
              echo "   sudo sunxi-fel uboot $(sudo find /nix/store/ -iname *u-boot-sunxi-with-spl*)"
              echo "========================================================="
            '';
          };
      });
}
