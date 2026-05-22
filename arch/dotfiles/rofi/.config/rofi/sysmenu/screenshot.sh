#!/bin/bash

source ~/.config/rofi/common/generic.sh

SCREEN_SHOT_DIR=$HOME/Pictures/Screenshots
test -d $SCREEN_SHOT_DIR || mkdir -p $SCREEN_SHOT_DIR
pkill slurp && exit 0
pkill rofi

get_rectangles() {
  local active_workspace=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .activeWorkspace.id')
  hyprctl monitors -j | jq -r --arg ws "$active_workspace" '.[] | select(.activeWorkspace.id == ($ws | tonumber)) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"'
  hyprctl clients -j | jq -r --arg ws "$active_workspace" '.[] | select(.workspace.id == ($ws | tonumber)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

opt_region="󰩬 Select region"
opt_window="󰍽 Select window"
opt_fullscreen=" Fullscreen"

main_menu="$opt_region\n$opt_window\n$opt_fullscreen"
selected_mode=$(_runrofimenu "$main_menu" "Take Screenshot" "󰄀")

case $selected_mode in
    $opt_region)
        pkill rofi
        sleep 0.1
        wayfreeze & WFPID=$!
        rect_seclectd=$(slurp 2>/dev/null)
        kill $WFPID 2>/dev/null
        ;;
    $opt_window)
        pkill rofi
        sleep 0.1
        wayfreeze & WFPID=$!
        rect_seclectd=$(get_rectangles | slurp -r 2>/dev/null)
        kill $WFPID 2>/dev/null
        ;;
    $opt_fullscreen)
        pkill rofi
        sleep 0.1
        rect_seclectd=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"')
        ;;
    *)
        exit 0
        ;;
esac


grim -g "$rect_seclectd" - |
  satty --filename - \
    --output-filename "$SCREEN_SHOT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png" \
    --early-exit \
    --actions-on-enter save-to-clipboard \
    --save-after-copy \
    --copy-command 'wl-copy'h