#!/usr/bin/env bash
# Bootstrap + rebuild script.  Idempotent — safe to re-run.
#
# configuration.nix imports /etc/nixos/hardware-configuration.nix via an
# absolute path so this repo stays machine-agnostic.  That import is impure
# (outside the flake source), so nixos-rebuild needs --impure.
#
# /etc/nixos/hardware-configuration.nix is created by nixos-install during the
# initial OS install.  On a fresh laptop where it's somehow missing, this
# script regenerates it.
set -euo pipefail

cd "$(dirname "$0")"

HW="/etc/nixos/hardware-configuration.nix"

test -f "$HW" || sudo nixos-generate-config --show-hardware-config \
  | sudo tee "$HW" >/dev/null

sudo nixos-rebuild switch --flake ".#nixos" --impure
