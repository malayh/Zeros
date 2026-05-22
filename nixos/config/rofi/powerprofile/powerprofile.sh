#!/usr/bin/env bash

source ~/.config/rofi/common/generic.sh


getoptions() {
	options=$(powerprofilesctl list |awk '/^\s*[* ]\s*[a-zA-Z0-9\-]+:$/ { gsub(/^[*[:space:]]+|:$/,""); print }' | tac)
	selected_profile=$(powerprofilesctl get)
	sed -e "s/^$selected_profile\$/$selected_profile ✔/" <<< "$options"
}

chosen=$(_runrofimenu "$(getoptions)" "Power Profile" "")
chosen=$(sed 's/ ✔$//' <<< "$chosen")
if [ -n "$chosen" ]; then
	powerprofilesctl set "$chosen"
fi