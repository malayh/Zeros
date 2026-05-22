#!/usr/bin/env bash
# Bootstrap + rebuild script. Idempotent — safe to re-run.
#
# hardware-configuration.nix is NOT tracked in git: it's regenerated per machine
# the first time this script runs, then reused on subsequent rebuilds.  Delete
# it by hand if hardware changes (new disk, new partitioning) and re-run.
set -euo pipefail

# Always operate from the script's own directory so $HW and the flake path
# resolve correctly regardless of where this script is invoked from.
cd "$(dirname "$0")"

HW="./hardware-configuration.nix"

# `--show-hardware-config` inspects the running system (/proc/mounts, lsblk,
# loaded modules) and prints a complete hardware-configuration.nix to stdout.
# `--root <dir>` is for the installer ISO flow where you've mounted the new
# root at <dir>; pointing it at an empty tmpdir silently omits fileSystems.
test -f $HW || sudo nixos-generate-config --show-hardware-config > "$HW"

sudo nixos-rebuild switch --flake ".#nixos"
