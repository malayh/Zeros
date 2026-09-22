#!/bin/bash

source ~/.config/rofi/common/generic.sh

IFS=: read -r -a xdg_data_paths <<< "${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
declare -a icon_paths application_paths desktop_files

for data_path in "${xdg_data_paths[@]}"; do
    [[ -d $data_path/icons ]] && icon_paths+=("$data_path/icons")
    [[ -d $data_path/pixmaps ]] && icon_paths+=("$data_path/pixmaps")
    [[ -d $data_path/applications ]] && application_paths+=("$data_path/applications")
done

if (( ${#application_paths[@]} )); then
    mapfile -d '' -t desktop_files < <(find -L "${application_paths[@]}" \
        -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)
fi

find_icon_file() {
    local name=$1 icon

    [[ $name == /* && -f $name ]] && { printf '%s' "$name"; return; }
    (( ${#icon_paths[@]} )) || return 1

    icon=$(find -L "${icon_paths[@]}" -type f \
        \( -name "$name" -o -name "$name.png" -o -name "$name.svg" -o -name "$name.xpm" \) \
        -print -quit 2>/dev/null)
    [[ -n $icon ]] && { printf '%s' "$icon"; return; }

    return 1
}

desktop_icon_for_class() {
    local app=${1,,} short=${1##*.} desktop desktop_id icon
    short=${short,,}

    for desktop in "${desktop_files[@]}"; do
        desktop_id=${desktop##*/}
        desktop_id=${desktop_id%.desktop}
        desktop_id=${desktop_id,,}
        [[ $desktop_id == "$app" || $desktop_id == "$short" ]] && break
        desktop=""
    done

    if [[ -z $desktop && ${#desktop_files[@]} -gt 0 ]]; then
        desktop=$(grep -ilxF "StartupWMClass=$app" "${desktop_files[@]}" 2>/dev/null | head -n 1)
    fi

    [[ -n $desktop ]] || return 1
    icon=$(awk '
        /^\[Desktop Entry\]$/ { entry = 1; next }
        /^\[/ && entry { exit }
        entry && /^Icon=/ { sub(/^[^=]*=/, ""); print; exit }
    ' "$desktop")
    [[ -n $icon ]] && printf '%s' "$icon"
}

resolve_app_icon() {
    local app=$1 icon

    if [[ $app != "[unknown app]" ]] && icon=$(find_icon_file "$app"); then
        printf '%s' "$icon"
    elif [[ $app != "[unknown app]" ]] && icon=$(desktop_icon_for_class "$app"); then
        find_icon_file "$icon" || printf '%s' "$icon"
    elif [[ $app != "[unknown app]" ]]; then
        printf '%s' "$app"
    else
        printf '%s' "application-x-addon"
    fi
}

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

declare -A app_icons
options=""

while IFS=$'\x1f' read -r title workspace app; do
    [[ ${app_icons[$app]+cached} ]] || app_icons[$app]=$(resolve_app_icon "$app")
    [[ -n $options ]] && options+=$'\n'
    printf -v row '%s — %s\\0icon\\x1f%s\\x1fmeta\\x1f%s' \
        "$title" "$workspace" "${app_icons[$app]}" "$app"
    options+=$row
done < <(jq -r '
    def clean($fallback):
        gsub("[\\t\\r\\n\u001f]+"; " ")
        | if length > 0 then . else $fallback end;

    .[]
    | ((.class // .initialClass // "") | clean("[unknown app]")) as $app
    | [
        ((.title // "") | clean("[untitled]")),
        ((.workspace.name // .workspace.id // "unknown") | tostring | clean("unknown")),
        $app
    ]
    | join("\u001f")
' <<< "$clients")

selected=$(_runrofimenu "$options" "Windows" "󰖯" i) || exit 0
[[ $selected =~ ^[0-9]+$ ]] || exit 0
(( selected < $(jq 'length' <<< "$clients") )) || exit 0

address=$(jq -r --argjson index "$selected" '.[$index].address // empty' <<< "$clients")
[[ $address =~ ^0x[[:xdigit:]]+$ ]] || exit 0

hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1
