{
  description = "Development environment for NextThingCo C.H.I.P. Flashing Tools";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          system = system;
          config = { allowUnfree = true; };
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "chip-tools-env";

          # Tools required to run the repo's flashing scripts
          nativeBuildInputs = with pkgs; [
            git
            curl
            sunxi-tools      # Crucial: Provides 'sunxi-fel' for flashing Allwinner SoCs
            android-tools    # Provides 'fastboot' often invoked by Allwinner flash scripts
            picocom          # Reliable serial console emulator for testing UART console (115200 baud)
            libusb1          # Essential backend dependency for sunxi-fel communicating over USB
            pkg-config

            # Common scripting and formatting dependencies for the wrapper tools
            bashInteractive
            coreutils
            gnused
            gawk
          ];

          shellHook = ''
            echo "========================================================="
            echo "  ⚡ C.H.I.P. Hardware Tools Dev Environment Loaded ⚡  "
            echo "========================================================="
            
            # Auto-clone the target repository if it doesn't already exist locally
            REPO_DIR="chip-tools"
            if [ ! -d "$REPO_DIR" ]; then
              echo "⚙️ Cloning joelguittet/chip-tools repository..."
              git clone https://github.com/joelguittet/chip-tools.git "$REPO_DIR"
            else
              echo "✅ Repository folder '$REPO_DIR' already present."
            fi

            echo ""
            echo "👉 To interface with your C.H.I.P. or C.H.I.P. Pro over serial:"
            echo "   picocom -b 115200 /dev/ttyUSB0 (or /dev/ttyACM0)"
            echo ""
            echo "⚠️  NOTE: Running 'sunxi-fel' or executing flashing scripts"
            echo "   requires USB access privileges. You may need 'sudo' or specific udev rules."
            echo "========================================================="
          '';
        };
      });
}
