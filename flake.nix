{
  description = "Development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Repo tooling (formatters, hooks, linters).
        devTools = with pkgs; [
          git
          just
          pre-commit
          shfmt
          shellcheck
          yamllint
          prettier
          nixpkgs-fmt
        ];

        # Runtime dependencies the shell shells out to, so `nix develop` can run
        # and test it. Mirrors the ansible role (ansible/roles/quickshell).
        pythonSwap = pkgs.python3.withPackages (ps: with ps; [ pillow imagehash ]);
        runtimeDeps = with pkgs; [
          quickshell # the shell itself
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
          # ships with the proprietary driver, so it's intentionally not declared
          # here (driver packaging is host/hardware specific).
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = devTools ++ runtimeDeps;
          # Wire the repo into git on shell entry.
          shellHook = ''
            command -v pre-commit >/dev/null && \
              pre-commit install --hook-type pre-commit --hook-type commit-msg 2>/dev/null || true
          '';
        };
      });
}
