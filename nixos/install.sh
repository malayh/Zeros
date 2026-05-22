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

# Compute resume_offset for hibernation.  The offset is the physical block of
# the first extent of /var/lib/swapfile within the root fs; it's machine-local
# and can change if the swapfile is ever recreated, so we recompute it every
# run.  Skipped on a brand-new system where the swapfile hasn't been created
# yet — the next rebuild creates it, and the following install.sh writes the
# offset.
if [[ -f /var/lib/swapfile ]]; then
  OFFSET=$(sudo filefrag -v /var/lib/swapfile \
    | awk '$1=="0:" {sub(/\.\.$/,"",$4); print $4; exit}')
  printf '%s' "$OFFSET" | sudo tee /etc/nixos/resume-offset >/dev/null
fi

sudo nixos-rebuild switch --flake ".#nixos" --impure
