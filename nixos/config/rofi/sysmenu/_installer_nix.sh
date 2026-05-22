#!/bin/bash

# Read-only nix-search browser. Prompts for a query, runs `nix search nixpkgs`,
# pipes results into fzf with description preview. Installing requires editing
# the NixOS / home-manager config — this is intentional.

read -r -p "Search nixpkgs for: " query
[ -z "$query" ] && exit 0

results=$(nix search nixpkgs "$query" --json 2>/dev/null \
  | jq -r 'to_entries[] | "\(.key)\t\(.value.description // "")"')

if [ -z "$results" ]; then
  echo "No results."
  read -p "Press [Enter] to exit..."
  exit 0
fi

selected=$(echo "$results" | fzf \
  --delimiter='\t' \
  --with-nth=1,2 \
  --preview 'echo {} | tr "\t" "\n"' \
  --preview-window='down:30%:wrap' \
  --bind 'alt-p:toggle-preview' \
  --color 'pointer:green,marker:green')

if [ -n "$selected" ]; then
  attr=$(echo "$selected" | cut -f1)
  echo
  echo "Selected: $attr"
  echo
  echo "Add this attribute to environment.systemPackages or home.packages, then"
  echo "rebuild with: sudo nixos-rebuild switch --flake ~/Zeros/nixos#nixos"
  read -p "Press [Enter] to exit..."
fi
