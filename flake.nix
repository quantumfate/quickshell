{
  description = "quantumfate Quickshell desktop — dual delivery (nix modules + devShell)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Runtime deps the shell shells out to / links, shared by the nixos module
      # and the devShell. Mirrors ansible/roles/quickshell.
      runtimeDeps = pkgs:
        let
          # dofus_swap.py image matching.
          pythonSwap = pkgs.python3.withPackages (ps: with ps; [ pillow imagehash ]);
        in
        with pkgs; [
          quickshell # the shell itself
          qt6.qt5compat # Qt5Compat.GraphicalEffects (blur/shadow) — not a quickshell hard dep
          upower # Quickshell.Services.UPower (battery/power)
          jq # store queries + workspace probe (Hypr/SysStats)
          libnotify # notify-send → Notify daemon (org.freedesktop.Notifications)
          xdotool # window rename / retitle
          networkmanager # SysStats wifi probe (nmcli)
          iproute2 # SysStats default-iface probe (ip route)
          gawk # SysStats probe field parsing (awk)
          procps # DofusSwap detector state (pgrep/pkill)
          util-linux # DofusSwap detached launch (setsid)
          curl # Weather widget (wttr.in)
          xdg-utils # Weather click (xdg-open)
          uwsm # session-scoped launches from bindings
          grim # dofus_swap.py capture
          slurp # dofus_swap.py region calibrate
          pythonSwap # python + pillow + imagehash (dofus_swap.py)
          nerd-fonts.jetbrains-mono # bar font + glyphs
          # GPU stats (SysMonitor/SysPanel) use `nvidia-smi` when present — it
          # ships with the proprietary driver, host-specific, so not declared.
        ];
    in
    # System-agnostic outputs: modules other flakes/home-manager import.
    {
      # NixOS module — system scope: the shell's runtime packages.
      nixosModules.quickshell = { config, lib, pkgs, ... }:
        let cfg = config.programs.quickshellDesktop;
        in {
          options.programs.quickshellDesktop.enable =
            lib.mkEnableOption "the quantumfate Quickshell desktop (system packages)";
          config = lib.mkIf cfg.enable {
            environment.systemPackages = runtimeDeps pkgs;
          };
        };

      # home-manager module — user scope: deploy the config + completions.
      homeManagerModules.quickshell = { config, lib, pkgs, ... }:
        let cfg = config.programs.quickshellDesktop;
        in {
          options.programs.quickshellDesktop = {
            enable = lib.mkEnableOption "deploy the quantumfate Quickshell config";
            name = lib.mkOption {
              type = lib.types.str;
              default = "quantumfate";
              description = "Config name: deployed at ~/.config/quickshell/<name>, run with `qs -c <name>`.";
            };
          };
          config = lib.mkIf cfg.enable {
            # Deploy the repo as the named quickshell config (matches the symlink).
            xdg.configFile."quickshell/${cfg.name}".source = self;
            # zsh completions read by the user's fpath.
            home.file.".local/share/zsh/site-functions/_qs".source = self + "/completions/_qs";
            home.file.".local/share/zsh/site-functions/_qfs".source = self + "/completions/_qfs";
          };
        };
    }
    # Per-system outputs: the dev / CI shell.
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Repo tooling for editing + CI (formatters, linters, ansible checks).
        devTools = with pkgs; [
          git
          just
          pre-commit
          shfmt
          shellcheck
          yamllint
          prettier
          nixpkgs-fmt
          ansible
          ansible-lint
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = devTools ++ runtimeDeps pkgs;
          shellHook = ''
            command -v pre-commit >/dev/null && \
              pre-commit install --hook-type pre-commit --hook-type commit-msg 2>/dev/null || true
          '';
        };
      });
}
