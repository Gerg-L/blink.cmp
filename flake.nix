{
  description = "Performant, batteries-included completion plugin for Neovim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        {
          self',
          inputs',
          pkgs,
          system,
          lib,
          ...
        }:
        {
          # use fenix overlay
          _module.args.pkgs = import nixpkgs {
            inherit system;
            overlays = [ inputs.fenix.overlays.default ];
          };

          # define the packages provided by this flake
          packages =

            {
              blink-cmp-fuzzy-lib =
                let
                  inherit (inputs'.fenix.packages.minimal) toolchain;
                  rustPlatform = pkgs.makeRustPlatform {
                    cargo = toolchain;
                    rustc = toolchain;
                  };
                in
                rustPlatform.buildRustPackage (finalAttrs: {
                  name = "${finalAttrs.pname}-${finalAttrs.version}";
                  pname = "blink.cmp";
                  version = "1.3.1";

                  src =
                    let
                      fs = lib.fileset;
                    in
                    fs.toSource {
                      root = ./.;
                      fileset = fs.unions [
                        (fs.fileFilter (file: file.hasExt "txt") ./doc)
                        ./lua
                        ./plugin
                        ./Cargo.lock
                        ./Cargo.toml
                      ];

                    };

                  cargoLock.lockFile = ./Cargo.lock;

                  buildInputs =
                    with pkgs;
                    lib.optionals stdenv.hostPlatform.isAarch64 [
                      rust-jemalloc-sys
                    ]; # revisit once https://github.com/NixOS/nix/issues/12426 is solved
                  nativeBuildInputs = with pkgs; [ git ];

                  # don't move /doc
                  forceShare = [ ];

                  postInstall = ''
                    shopt -s extglob
                    cp -r ./!(target) "$out"
                    mkdir -p "$out/target"
                    mv "$out/lib" "$out/target/release"
                  '';
                });

              default = self'.packages.blink-cmp;
            };

          # builds the native module of the plugin
          apps.build-plugin = {
            type = "app";
            program =
              let
                buildScript = pkgs.writeShellApplication {
                  name = "build-plugin";
                  runtimeInputs = with pkgs; [
                    fenix.minimal.toolchain
                    gcc
                  ];
                  text = ''
                    export LIBRARY_PATH="${lib.makeLibraryPath [ pkgs.libiconv ]}";
                    cargo build --release
                  '';
                };
              in
              lib.getExe buildScript;
          };

          # define the default dev environment
          devShells.default = pkgs.mkShell {
            name = "blink";
            inputsFrom = [
              self'.packages.blink-cmp
              self'.apps.build-plugin
            ];
            packages = with pkgs; [ rust-analyzer-nightly ];
          };

          formatter = pkgs.nixfmt-classic;
        };
    };

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs"
    ];
  };
}
