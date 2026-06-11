#!/bin/bash

# nixpkgs is too large to list like `yay -Slqa`, so prompt for a query first.
read -r -p "Search nixpkgs for: " query
[ -z "$query" ] && exit 0

json=$(nix search nixpkgs "$query" --json 2>/dev/null)
rekeyed=$(echo "$json" | jq 'with_entries(.key |= sub("^legacyPackages\\.[^.]+\\."; ""))')
results=$(echo "$rekeyed" | jq -r 'to_entries[] | "\(.key)\t\(.value.description // "")"')

if [ -z "$results" ]; then
  echo "No results."
  read -p "Press [Enter] to exit..."
  exit 0
fi

db=$(mktemp)
fast=$(mktemp)
full=$(mktemp)
trap 'rm -f "$db" "$fast" "$full"' EXIT
echo "$rekeyed" >"$db"
chmod +x "$fast" "$full"

cat >"$fast" <<EOF
#!/bin/bash
jq -r --arg a "\$1" '.[\$a] | "Attribute:   \(\$a)\nVersion:     \(.version // "?")\n\nDescription:\n\(.description // "(none)")"' "$db"
EOF

cat >"$full" <<EOF
#!/bin/bash
a="\$1"
echo "Attribute:   \$a"
echo "Version:     \$(NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --raw nixpkgs#\$a.version 2>/dev/null)"
echo "Homepage:    \$(NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --raw nixpkgs#\$a.meta.homepage 2>/dev/null)"
echo "License:     \$(NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --raw nixpkgs#\$a.meta.license.fullName 2>/dev/null)"
echo
NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --raw nixpkgs#\$a.meta.longDescription 2>/dev/null \
  || NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --raw nixpkgs#\$a.meta.description 2>/dev/null
EOF

fzf_args=(
  --multi
  --delimiter='\t'
  --with-nth=1,2
  --preview "$fast {1}"
  --preview-label='alt-p: toggle preview, alt-b/B: toggle full meta, alt-j/k: scroll, tab: multi-select'
  --preview-label-pos='bottom'
  --preview-window 'down:65%:wrap'
  --bind 'alt-p:toggle-preview'
  --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
  --bind 'alt-k:preview-up,alt-j:preview-down'
  --bind "alt-b:change-preview:$full {1}"
  --bind "alt-B:change-preview:$fast {1}"
  --color 'pointer:green,marker:green'
)

selected=$(echo "$results" | fzf "${fzf_args[@]}")

if [ -n "$selected" ]; then
  mapfile -t attrs < <(printf '%s\n' "$selected" | cut -f1)
  installables=()
  for a in "${attrs[@]}"; do
    installables+=("nixpkgs#$a")
  done
  NIXPKGS_ALLOW_UNFREE=1 nix profile add --impure "${installables[@]}"
  read -p "Done. Press [Enter] to exit..."
fi
