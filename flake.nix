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
              cp -r shell.qml services modules assets completions "$dest/"
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
            enableZshCompletions = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Install the _qs/_qfs zsh completions and add them to fpath (needs programs.zsh).";
            };
          };

          config = lib.mkIf cfg.enable (lib.mkMerge [
            {
              # Symlink the whole config tree into place. State files live in
              # $XDG_STATE_HOME and are self-seeded by the shell, so nothing here
              # is written at runtime except the git-ignored .qmlls.ini (harmless
              # if the store path is read-only).
              xdg.configFile."quickshell/${cfg.name}".source = self;

              # Runtime deps: the shell, jq (store queries), libnotify
              # (notify-send IPC bindings), xdotool (window rename + launch).
              home.packages = [
                cfg.package
                pkgs.jq
                pkgs.libnotify
                pkgs.xdotool
              ];
            }

            (lib.mkIf cfg.enableZshCompletions {
              home.file.".local/share/zsh/site-functions/_qs".source = ./completions/_qs;
              home.file.".local/share/zsh/site-functions/_qfs".source = ./completions/_qfs;
              # Put the dir on fpath before compinit. Requires programs.zsh; for
              # HM < 25.05 use initExtraBeforeCompInit instead of initContent.
              programs.zsh.initContent = lib.mkOrder 550 ''
                fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
              '';
            })
          ]);
        };
    };
}
