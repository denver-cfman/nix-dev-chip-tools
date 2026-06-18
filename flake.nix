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
          inherit system;
          config = { allowUnfree = true; };
        };
      in
      {
        devShells.default = 
          # This assertion blocks evaluation completely on Apple Silicon
          assert pkgs.stdenv.hostPlatform.system != "aarch64-darwin" || 
            builtins.throw "❌ Error: chip-tools does not support aarch64-darwin. It requires a Linux platform for raw USB flashing tooling.";
          
          pkgs.mkShell {
            name = "chip-tools-env";

            nativeBuildInputs = with pkgs; [
              git
              curl
              sunxi-tools
              android-tools
              picocom
              libusb1
              pkg-config
            ];

            shellHook = ''
              echo "⚡ Environment Loaded Successfully ⚡"
            '';
          };
      });
}
