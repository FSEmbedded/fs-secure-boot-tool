#!/bin/bash

# define some global variables
BOLD='\033[1m'
NORMAL='\033[0m'
LIGHT_GREEN='\033[1;32m'
LIGHT_RED='\033[0;31m'
CLEAR="\ec"

# check if environment variable is set
if [ -z "${CST_DIR}" ]; then
    printf "***Please set ${BOLD}CST_DIR${NORMAL} in envionment variables***\b\n"
    exit 1
fi

printf "Do you want to ${BOLD}create${NORMAL} certificates, create ${BOLD}jtag${NORMAL} response key, ${BOLD}sign${NORMAL} an image or ${BOLD}encrypt${NORMAL} an image ${BOLD}(c/j/s/e)${NORMAL}?\b\n"
printf "Note: When an image is encrypted it's also signed!\b\n"
read action

if [ "$action" != "c" ] && [ "$action" != "s" ] && [ "$action" != "e" ] && [ "$action" != "j" ]; then
    printf "${BOLD}command not supported!${NORMAL}\b\n"
    exit 1
fi

if [ "$action" == "c" ]; then
    ./makeAction.sh --settings=$settings --action=$action --cst-dir="${CST_DIR}"
    exit 0
elif [ "$action" == "j" ]; then
    chrlen=0
    #read JTAG responsible key
    printf "Please enter the response key ${BOLD}(7 Byte) (Little-Endian)${NORMAL} and confirm it with enter\b\n"

    #check if length is correct
    while [ $chrlen != 14 ]
    do
        read jtag_key

        chrlen=${#jtag_key}

        if [ $chrlen != 14 ]; then
            printf "wrong length, try again!\b\n"
        fi
    done

    #check if values are hex values
    if ! [[ $jtag_key =~ [a-f0-9]{$chrlen} ]]; then
        printf "No hex value, exit!"
        exit 1
    fi

    ./makeAction.sh --action="$action" --jtag-resp-key="$jtag_key" --cst-dir="$CST_DIR"
    exit 0
fi


printf "Do you want to use the ${BOLD}default${NORMAL} or ${BOLD}custom${NORMAL} settings ${BOLD}(d/c)${NORMAL}?\b\n"
read settings

if [ "$settings" == "c" ]; then

    printf "Enter output name:\b\n"
    read name

    printf "Enter Loadaddress (Hex):\b\n"
    printf "Note: Type your Loadaddress without 0x at the beginning!\b\n"
    read load

fi

select cpu in "FSIMX6SDQ" "FSIMX6SX" "FSIMX6UL" "FSIMX6ULL" "FSVYBRID";
do
    case "$cpu" in
	FSIMX6SDQ )
	    cpu=1
	    break
	    ;;
	FSIMX6SX )
	    cpu=2
	    break
	    ;;
	FSIMX6UL )
	    cpu=3
	    break
	    ;;
	FSIMX6ULL )
	    cpu=4
	    break
	    ;;
	FSVYBRID )
	    cpu=5
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
    ./makeAction.sh --loadaddr="$load" --pad-to="$pad" --output="$name" --cpu="$cpu" --action="$action" --image-path="$image_path" --cst-dir="$CST_DIR"
    exit 0

elif [ "$action" == "e" ]; then
    master_key="o"
    printf "Enter key length ${BOLD}(128/192/256):${NORMAL}\b\n"
    read key_length
    if [ $key_length != 128 ] && [ $key_length != 192 ] && [ $key_length != 256 ]; then
	printf "${BOLD}wrong key length!${NORMAL}\b\n"
	exit 1
    fi
    ./makeAction.sh --loadaddr="$load" --pad-to="$pad" --output="$name" --cpu="$cpu" --action="$action" --image-path="$image_path" --key-length="$key_length" --master-key="$master_key" --cst-dir="$CST_DIR"
fi

exit 0
