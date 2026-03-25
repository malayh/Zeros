#!/bin/bash

source ~/.config/rofi/common/generic.sh

options=$(cliphist list)
chosen=$(_runrofimenu "$options" "Clipboard History" "")
echo "$chosen" | cliphist decode | wl-copy


is_terminal=false

if [ "$XDG_SESSION_DESKTOP" = "Hyprland" ] || [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    active_class=$(hyprctl activewindow -j | jq -r '.class // empty' | tr '[:upper:]' '[:lower:]')
    if [[ "$active_class" =~ (alacritty|kitty|foot|gnome-terminal|terminator|wezterm|konsole|xterm) ]]; then
        is_terminal=true
    fi
fi


if $is_terminal; then
    wtype -M ctrl -M shift -k v -m shift -m ctrl
else
    wtype -M ctrl -k v -m ctrl
fi