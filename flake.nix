{
  description = "Hytale Launcher - Official launcher for Hytale game";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        packages = pkgs.callPackage ./package.nix { };
      in {
        packages = {
          default = packages.hytale-launcher;
          inherit (packages) hytale-launcher hytale-launcher-unwrapped;
        };

        apps.default = {
          type = "app";
          program = "${packages.hytale-launcher}/bin/hytale-launcher";
        };
      }
    );
}
