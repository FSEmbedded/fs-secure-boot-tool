#!/bin/bash

# define some global variables
BOLD='\033[1m'
NORMAL='\033[0m'
LIGHT_GREEN='\033[1;32m'
LIGHT_RED='\033[0;31m'
CLEAR="\ec"


printf "Do you want to ${BOLD}create${NORMAL} certificates, ${BOLD}sign${NORMAL} an image or ${BOLD}encrypt${NORMAL} an image ${BOLD}(c/s/e)${NORMAL}?\b\n"
printf "Note: When an image is encrypted it's also signed!\b\n"
read action

if [ "$action" == "c" ]; then
    ./makeAction.sh --settings=$settings --action=$action
    exit 0
fi


printf "Do you want to use the ${BOLD}default${NORMAL} or ${BOLD}custom${NORMAL} settings ${BOLD}(d/c)${NORMAL}?\b\n"
read settings

if [ "$settings" == "c" ]; then

    printf "Enter output name:\b\n"
    read name

    printf "Enter Loadaddress (Hex):\b\n"
    read load

fi

select cpu in "FSIMX6SDQ" "FSIMX6UL/SX" "FSIMX6VYBRID";
do
    case "$cpu" in
	FSIMX6SDQ )
	    cpu=1
	    break
	    ;;
	FSIMX6UL/SX )
	    cpu=2
	    break
	    ;;
	FSIMX6VYBRID )
	    cpu=3
	    break
	    ;;
    esac
done

if [ "$use_auto_serial" = "y" ]; then

    printf "Enter serial device name:\b\n"
    read serial_device

fi

printf "Enter image path ${BOLD}(absolute path!)${NORMAL}\b\n"
read image_path

if [ "$action" == "s" ]; then
    ./makeAction.sh --devicetree-loadaddr="$load" --pad-to="$pad" --output="$name" --cpu="$cpu" --action="$action" --image-path="$image_path"
    exit 0

elif [ "$action" == "e" ]; then
    printf "Enter key length ${BOLD}(128/192/256):${NORMAL}\b\n"
    read key_length
    ./makeAction.sh --devicetree-loadaddr="$load" --pad-to="$pad" --output="$name" --cpu="$cpu" --action="$action" --image-path="$image_path" --key-length="$key_length"
fi

exit 0
