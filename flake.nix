{
  description = "Development environment for NextThingCo C.H.I.P. Flashing Tools";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Declaratively pull the flashing tools repository
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

        # Package the tools into the Nix store and patch them cleanly
        chip-tools = pkgs.stdenv.mkDerivation {
          pname = "chip-tools";
          version = "unstable";
          src = chip-tools-src;

          installPhase = ''
            mkdir -p $out/bin
            cp *.sh $out/bin/
            chmod +x $out/bin/*.sh
          '';

          postFixup = ''
            patchShebangs $out/bin/*.sh
          '';
        };
      in
      {
        packages.default = chip-tools;

        devShells.default = assert pkgs.stdenv.hostPlatform.system != "aarch64-darwin" || builtins.throw "❌ Error: chip-tools does not support aarch64-darwin. It requires a Linux platform for raw USB flashing tooling.";
          pkgs.mkShell {
            name = "chip-tools-env";

            nativeBuildInputs = with pkgs; [
              git
              curl
              sunxi-tools      # Crucial: Provides 'sunxi-fel' for flashing Allwinner SoCs
              android-tools    # Provides 'fastboot' often invoked by Allwinner flash scripts
              picocom          # Reliable serial console emulator for testing UART console (115200 baud)
              libusb1          # Essential backend dependency for sunxi-fel communicating over USB
              pkg-config
              bashInteractive
              coreutils
              gnused
              gawk
              chip-tools       # Injects your freshly patched flash scripts straight into your PATH
            ];

            shellHook = ''
              echo "========================================================="
              echo "  ⚡ C.H.I.P. Hardware Tools Dev Environment Loaded ⚡  "
              echo "========================================================="
              echo "✅ Flashing scripts are cleanly patched and ready in your PATH!"
              echo ""
              echo "👉 Run them directly from anywhere:"
              echo "   chip-flash-chip.sh"
              echo "   chip-flash-chip-pro.sh"
              echo ""
              echo "👉 To interface over serial:"
              echo "   picocom -b 115200 /dev/ttyUSB0"
              echo "========================================================="
            '';
          };
      });
}
