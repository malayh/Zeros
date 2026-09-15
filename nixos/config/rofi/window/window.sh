#!/bin/bash

source ~/.config/rofi/common/generic.sh

clients=$(hyprctl clients -j 2>/dev/null) || exit 0
clients=$(jq -c '
    [
        .[]
        | select(.mapped == true)
        | select(
            (.workspace.name // "") != "special"
            and ((.workspace.name // "") | startswith("special:") | not)
        )
    ]
    | sort_by(
        if (.focusHistoryID // -1) >= 0
        then .focusHistoryID
        else 2147483647
        end
    )
' <<< "$clients" 2>/dev/null) || exit 0

(( $(jq 'length' <<< "$clients") > 0 )) || exit 0

options=$(jq -r '
    def clean($fallback):
        gsub("[\\t\\r\\n]+"; " ")
        | if length > 0 then . else $fallback end;

    .[]
    | [
        ((.title // "") | clean("[untitled]")),
        ((.class // .initialClass // "") | clean("[unknown app]")),
        ("workspace " + ((.workspace.name // .workspace.id // "unknown") | tostring))
    ]
    | join(" — ")
' <<< "$clients") || exit 0

selected=$(_runrofimenu "$options" "Windows" "󰖯" i) || exit 0
[[ $selected =~ ^[0-9]+$ ]] || exit 0
(( selected < $(jq 'length' <<< "$clients") )) || exit 0

address=$(jq -r --argjson index "$selected" '.[$index].address // empty' <<< "$clients")
[[ $address =~ ^0x[[:xdigit:]]+$ ]] || exit 0

hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1
