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
          quickshell               # the shell itself
          jq                       # store queries + workspace probe
          libnotify                # notify-send bindings
          xdotool                  # window rename / retitle
          pamixer                  # Pulseaudio module
          networkmanager           # Network module (nmcli)
          networkmanagerapplet     # nm-connection-editor
          mako                     # Mako module (makoctl)
          grim                     # dofus_swap.py capture
          slurp                    # dofus_swap.py region calibrate
          pythonSwap               # python + pillow + imagehash (dofus_swap.py)
          nerd-fonts.jetbrains-mono # bar font + glyphs
        ];
      in {
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
