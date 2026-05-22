#!/bin/bash

# On NixOS, package management is declarative. This is a read-only nix-search
# browser — to actually install something, edit configuration.nix / home.nix.

xdg-terminal-exec --app-id=org.zeros.terminal $HOME/.config/rofi/sysmenu/_installer_nix.sh
