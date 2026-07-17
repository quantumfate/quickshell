# Task runner. Run `just` to list recipes.

default:
	@just --list

build:
	nix build

check:
	nix flake check

fmt:
	nix fmt
