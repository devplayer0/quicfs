{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
    crane.inputs.nixpkgs.follows = "nixpkgs";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";

    rootdir = {
      url = "file+file:///dev/null";
      flake = false;
    };
  };

  outputs =
    inputs@{
      nixpkgs, flake-parts, rust-overlay, crane,
      devenv,
      rootdir,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
        devenv.flakeModule
      ];
      systems = [ "x86_64-linux" ];

      debug = true;
      perSystem = { inputs', system, lib, pkgs, config, ... }:
      let
        inherit (lib) genAttrs;

        rustToolchain' = ps: ps.rust-bin.stable."1.80.0".default;
        rustToolchain = rustToolchain' pkgs;
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain';

        src = craneLib.cleanCargoSource ./.;
        commonArgs = {
          inherit src;
          strictDeps = true;

          nativeBuildInputs = with pkgs; [
            pkg-config
          ];
          buildInputs = with pkgs; [
            fuse3
          ];
        };
        # Build *just* the cargo dependencies, so we can reuse
        # all of that work when running in CI
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
      in
      {
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [
            rust-overlay.overlays.default
          ];
        };

        overlayAttrs = {
          inherit (config.packages) quicfs;
        };
        packages = rec {
          quicfs = craneLib.buildPackage (commonArgs // {
            inherit cargoArtifacts;
          });
          default = quicfs;
        };
        devenv.shells.default = devenvArgs:
        let
          cfg = devenvArgs.config;

          rootdirOpt =
            let
              rootFileContent = builtins.readFile rootdir.outPath;
            in
            pkgs.lib.mkIf (rootFileContent != "") rootFileContent;
        in
        {
          devenv.root = rootdirOpt;

          packages = with pkgs; [
            fuse3
            cargo-outdated
          ];

          languages = {
            c.enable = true;
            rust = {
              enable = true;
              channel = "nixpkgs";
              # HACK: This devenv module expects each component in a separate package,
              # but rust-overlay isn't really set up that way
              toolchain = genAttrs cfg.languages.rust.components (_: rustToolchain);
            };
          };
        };
      };
    };
}
