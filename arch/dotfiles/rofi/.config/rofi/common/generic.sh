#!/usr/bin/env bash

dir="$HOME/.config/rofi/common"


_runrofimenu() {
    menu_options=$1
    prompt=$2
    icon=$3

    echo -e "$menu_options" | rofi \
        -dmenu \
        -i \
        -p "$prompt" \
        -theme-str "textbox-prompt-colon {str: '$icon';}" \
        -theme ${dir}/generic.rasi
}

# Usage:
# _runrofimenu "Option 1\nOption 2\nOption 3" "System menu" ""