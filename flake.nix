{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    rust-overlay.url = "github:oxalica/rust-overlay";
    cargo2nix.url = "github:cargo2nix/cargo2nix";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, flake-parts, rust-overlay, cargo2nix, devshell, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
        devshell.flakeModule
      ];
      systems = [ "x86_64-linux" ];
      perSystem = { inputs', system, pkgs, config, ... }:
      let
        binlessFuse = pkgs.fuse3.overrideAttrs (old: {
          postFixup = old.postFixup + ''
            rm -r "$out"/{,s}bin
          '';
        });
        rustPkgs = pkgs.rustBuilder.makePackageSet {
          rustToolchain = pkgs.rust-bin.stable."1.72.1".default;
          packageFun = import ./Cargo.nix;
          packageOverrides = pkgs: pkgs.rustBuilder.overrides.all ++ [
            (pkgs.rustBuilder.rustLib.makeOverride {
              name = "fuser";
              overrideAttrs = drv: {
                propagatedBuildInputs = drv.propagatedBuildInputs ++ [
                  binlessFuse
                ];
              };
            })
          ];
        };
      in
      {
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [
            devshell.overlays.default
            cargo2nix.overlays.default
            rust-overlay.overlays.default
          ];
        };

        overlayAttrs = {
          inherit (config.packages) quicfs;
        };
        packages = rec {
          quicfs = (rustPkgs.workspace.quicfs { }).bin;
          default = quicfs;
        };
        devshells.default = {
          imports = [ "${pkgs.devshell.extraModulesDir}/language/c.nix" ];
          language.c = with pkgs; rec {
            compiler = gcc;
            libraries = [
              binlessFuse
            ];
            includes = libraries;
          };
          packagesFrom = [
            (rustPkgs.workspaceShell { })
          ];
          packages = [
            inputs'.cargo2nix.packages.default
          ];
        };
      };
    };
}
