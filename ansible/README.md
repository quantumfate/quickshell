# Ansible

Provisions this Quickshell config on a target (Arch): installs runtime packages,
symlinks the config into `~/.config/quickshell/<name>`, and ensures the state
dir. State files self-seed on first run, so nothing is copied.

## Run locally

```sh
ansible-galaxy collection install -r requirements.yml   # community.general (pacman)
ansible-playbook playbook.yml --ask-become-pass
```

## Import from a controller

The `quickshell` role (under `roles/`) is the reusable output — the Ansible
analogue of the flake's home-manager module. Add this repo to your controller
(git submodule or vendored), put `ansible/roles` on your `roles_path`, then:

```yaml
- hosts: workstation
  roles:
    - role: quickshell
      vars:
        quickshell_config_name: quantumfate
        quickshell_repo_path: /path/to/checkout
        quickshell_install_extra_packages: true   # Dofus swap tooling
```

## Variables

See `roles/quickshell/defaults/main.yml`. Key ones: `quickshell_config_name`,
`quickshell_repo_path`, `quickshell_install_packages`, `quickshell_packages`,
`quickshell_install_extra_packages`.
