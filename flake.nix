{
  description = "quantumfate Quickshell desktop config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, quickshell, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
            qs = quickshell.packages.${system}.default;
          }
        );
    in
    {
      # The config as a package: its QML tree under $out/share/quickshell/<name>.
      packages = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "quantumfate-quickshell";
            version = "0.1.0";
            src = self;
            dontBuild = true;
            installPhase = ''
              dest="$out/share/quickshell/quantumfate"
              mkdir -p "$dest"
              cp -r shell.qml services modules assets "$dest/"
            '';
          };
        }
      );

      # Dev shell for hacking on the config (shell + language server + tools).
      devShells = forAllSystems (
        { pkgs, qs, ... }:
        {
          default = pkgs.mkShell {
            packages = [
              qs
              pkgs.qt6.qtdeclarative # qmlls / qmllint
              pkgs.jq
              pkgs.libnotify
            ];
          };
        }
      );

      # home-manager module — the flake "output" a consumer imports, mirroring how
      # the Ansible role is imported by a controller:
      #
      #   imports = [ inputs.quantumfate-quickshell.homeManagerModules.default ];
      #   programs.quantumfate-quickshell.enable = true;
      homeManagerModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.quantumfate-quickshell;
        in
        {
          options.programs.quantumfate-quickshell = {
            enable = lib.mkEnableOption "the quantumfate Quickshell config";
            name = lib.mkOption {
              type = lib.types.str;
              default = "quantumfate";
              description = "Config name under ~/.config/quickshell (run with `qs -c <name>`).";
            };
            package = lib.mkOption {
              type = lib.types.package;
              default = quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "quickshell.packages.\${system}.default";
              description = "Quickshell package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            # Symlink the whole config tree into place. State files live in
            # $XDG_STATE_HOME and are self-seeded by the shell, so nothing here is
            # written to at runtime except the git-ignored .qmlls.ini (harmless if
            # the store path is read-only).
            xdg.configFile."quickshell/${cfg.name}".source = self;
            home.packages = [
              cfg.package
              pkgs.jq
              pkgs.libnotify
            ];
          };
        };
    };
}
