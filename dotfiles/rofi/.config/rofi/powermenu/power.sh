#!/usr/bin/env bash

source ~/.config/rofi/common/generic.sh

# CMDs
uptime="`uptime -p | sed -e 's/up //g'`"

# Options
shutdown=' Power off'
suspend=' Suspend'
reboot=' Reboot'
lock=' Lock'

yes=' Yes'
no='󰜺 Cancel'


# Execute Command
run_cmd() {
	yesno_options="$yes\n$no"
	selected="$(_runrofimenu "$yesno_options" "Are you sure?" "")"
	if [[ "$selected" == "$yes" ]]; then
		if [[ $1 == '--shutdown' ]]; then
			custom-close-hypr-windows
            systemctl poweroff --no-wall
		elif [[ $1 == '--reboot' ]]; then
			systemctl reboot
		elif [[ $1 == '--lock' ]]; then
			custom-lock-screen
		elif [[ $1 == '--suspend' ]]; then
			custom-lock-screen
			systemctl suspend
		fi
	else
		exit 0
	fi
}

options=$(echo -e "$lock\n$suspend\n$reboot\n$shutdown")
chosen="$(_runrofimenu "$options" "Power Menu" "")"

case ${chosen} in
    $shutdown)
		run_cmd --shutdown
        ;;
    $reboot)
		run_cmd --reboot
        ;;
	$suspend)
		run_cmd --suspend
		;;
    $lock)
		run_cmd --lock
        ;;
esac