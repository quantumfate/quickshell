# Task runner. Run `just` to list recipes.
# Recipes are generated from the detected toolchain; edit freely.

default:
	@just --list

# Reformat the tree in place
fmt:
	shfmt -w -i 4 .
	prettier --write '**/*.md'
	nixpkgs-fmt .

# Verify formatting without writing
fmt-check:
	shfmt -d -i 4 .
	prettier --check '**/*.md'
	nixpkgs-fmt --check .

# `--cached --others --exclude-standard` rather than a bare `git ls-files`: the
# latter lists only TRACKED files, so a brand-new .qml sails through every gate
# until the moment it is committed, and then fails. That is how a literal
# bottomMargin reached main.
#
# Guards the scale sweep: sizes and layout spacing name a step on Theme.fs /
# Theme.space, never a pixel count. A literal here is how the shell drifted back
# to being unresizable last time, and it is one grep to catch.
#
# The edge margins inside a `margins { top: N }` group are included because the
# first version of this rule missed them, and three surfaces carrying their own
# copy of the bar's height silently overlapped it the moment the bar grew.
tokens:
	#!/usr/bin/env bash
	set -euo pipefail
	if git ls-files --cached --others --exclude-standard '*.qml' | xargs grep -nE '(pixelSize|spacing|margins|[a-zA-Z]Margin):[[:space:]]*[0-9]|\b(top|bottom|left|right):[[:space:]]*[0-9]'; then
		echo "^ literal size/spacing — use Theme.fs.* / Theme.space.* instead" >&2
		exit 1
	fi
	# Same idea, for colour: a hex literal outside Theme.qml is a surface
	# painting its own colour instead of reading a semantic role, which is what
	# makes a palette swap a one-file edit. Theme.qml is exempt — it's the one
	# place a palette is allowed to name its own hex. A line that legitimately
	# draws a palette's own swatch can opt out with a trailing
	# `// tokens-color-ok: <reason>` comment; keep that narrow — reach for a new
	# role instead of the exemption when one is missing.
	if git ls-files --cached --others --exclude-standard '*.qml' ':!:services/Theme.qml' \
		| xargs grep -nE '#[0-9a-fA-F]{3,8}' \
		| grep -v 'tokens-color-ok:'; then
		echo "^ literal colour — use a Theme.* role instead, or add one if it's missing" >&2
		exit 1
	fi

# Does the shell actually load?
#
# qmllint cannot resolve the Quickshell plugin's types — that is why
# UncreatableType and UnresolvedType are disabled in .qmllint.ini — so a missing
# `import Quickshell.Io` passes every static check and then fails at startup with
# "IpcHandler is not a type". A qmldir added to a directory has the same shape of
# failure: it hides every type in that directory that it does not list.
#
# Both happened. Neither was caught by anything until the shell would not start.
# So the gate loads the real config and greps the log for a load failure.
smoke:
	#!/usr/bin/env bash
	set -euo pipefail
	log=$(mktemp)
	trap 'rm -f "$log"' EXIT
	timeout 20 qs -c quantumfate >"$log" 2>&1 &
	pid=$!
	sleep 6
	kill $pid 2>/dev/null || true
	wait $pid 2>/dev/null || true
	if grep -q "Failed to load configuration" "$log"; then
		grep -E "ERROR" "$log" >&2
		exit 1
	fi

# Unit tests. Node's built-in runner, no dependency to install. The specs load
# the real QML sources rather than copies, so a change to a palette or to the
# cheatsheet parser is covered the moment it lands.
test:
	node --test tests/

# QML static analysis. Must be Qt6's qmllint: on Arch the unprefixed binary on
# PATH is Qt5's and exits 255 on every file here, so the recipe resolves a
# version-6 one rather than trusting PATH. Categories are tuned in
# .qmllint.ini — the Quickshell plugin's types are unresolvable to qmllint and
# are off, and the existing findings are grandfathered at `info` so the gate
# gives a floor today instead of waiting on a 174-item cleanup.
qmllint:
	#!/usr/bin/env bash
	set -euo pipefail
	for c in qmllint6 /usr/lib/qt6/bin/qmllint "$(command -v qmllint || true)"; do
		if [ -x "$c" ] && "$c" --version 2>/dev/null | grep -q ' 6\.'; then
			exec "$c" -I . $(git ls-files '*.qml')
		fi
	done
	echo "no Qt6 qmllint found (tried qmllint6, /usr/lib/qt6/bin/qmllint, PATH)" >&2
	exit 1

# Static analysis
lint: qmllint tokens
	git ls-files '*.sh' '*.bash' | xargs -r shellcheck
	yamllint .

# CI/pre-commit gate: formatting + QML linting + the token rule + tests
# (shellcheck/yamllint stay advisory)
check: fmt-check qmllint tokens test smoke
	@../hypr/bin/,privacy-check


# Ansible playbook syntax check (cheap; part of the CI gate)
ansible-syntax:
	ansible-playbook ansible/playbook.yml --syntax-check

# Validate the ansible delivery path (syntax + lint) — advisory, not gated
check-ansible: ansible-syntax
	ansible-lint ansible/

# Validate the nix delivery path (evaluates modules + devShell)
check-nix:
	nix flake check

# CI gate: formatting + ansible syntax (lint stays advisory, per `lint` above)
check-all: check ansible-syntax

# Bootstrap the local dev environment (hooks, toolchain, PATH)
setup:
	./scripts/setup.sh

# Install the system toolchain via ansible (needs sudo)
provision:
	ansible-playbook scripts/provision.yml --ask-become-pass

# Enter the reproducible nix dev shell
dev:
	nix develop
