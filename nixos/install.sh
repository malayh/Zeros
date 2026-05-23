#!/usr/bin/env bash
# Bootstrap + rebuild dispatcher.  Reads ./.env for NIX_DEVICE, then rebuilds
# against the matching nixosConfigurations entry.  Each device is a directory
# under devices/ containing <name>/<name>.nix; the flake auto-discovers them.
#
# To bring up a new device:
#   1) mkdir devices/<name> && create devices/<name>/<name>.nix
#   2) set NIX_DEVICE=<name> in .env
#   3) ./install.sh
#
# .env is gitignored — each physical machine sets its own.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "error: missing .env at $(pwd)/.env" >&2
  echo "       create one with: NIX_DEVICE=<device-name>" >&2
  exit 1
fi

set -a; source ./.env; set +a
: "${NIX_DEVICE:?.env must set NIX_DEVICE}"

DEV_FILE="devices/${NIX_DEVICE}/${NIX_DEVICE}.nix"
if [[ ! -f "$DEV_FILE" ]]; then
  echo "error: no device module at $DEV_FILE" >&2
  exit 1
fi

# /etc/nixos/hardware-configuration.nix is created by nixos-install during
# the initial OS install.  On a fresh laptop where it's somehow missing,
# regenerate it.  The device module imports it via an absolute path (impure),
# which is why nixos-rebuild needs --impure below.
HW="/etc/nixos/hardware-configuration.nix"
test -f "$HW" || sudo nixos-generate-config --show-hardware-config \
  | sudo tee "$HW" >/dev/null

# Record the flake working-tree path so impure modules can locate the live
# source tree (used to point user-config symlinks at git-tracked files instead
# of read-only /nix/store copies — see devices/g14/g14.nix rogConfigLink).
# Same pattern as resume-offset below: machine-local fact written here, read
# by the module via builtins.readFile under --impure.
printf '%s' "$(pwd)" | sudo tee /etc/nixos/flake-root >/dev/null

# Recompute resume_offset for hibernation if this device has a swapfile.
# The offset is the physical block of the first extent of /var/lib/swapfile
# within the root fs; it's machine-local and can change if the swapfile is
# ever recreated, so we recompute it every run.  Devices without hibernate
# don't create the swapfile and this block silently no-ops.
if [[ -f /var/lib/swapfile ]]; then
  OFFSET=$(sudo filefrag -v /var/lib/swapfile \
    | awk '$1=="0:" {sub(/\.\.$/,"",$4); print $4; exit}')
  printf '%s' "$OFFSET" | sudo tee /etc/nixos/resume-offset >/dev/null
fi

sudo nixos-rebuild switch --flake ".#${NIX_DEVICE}" --impure
