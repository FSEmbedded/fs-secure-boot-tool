#!/bin/bash


###############################################################################
# function: handleParameters()
#
# parameters: -
#
# return: -
#
# description:
# This functions stores the script parameters in global(!) vairables.
#
###############################################################################
function handleParameters()
{
    JTAG_KEY=$1
}


###############################################################################
# function: handleParameters()
#
# parameters: -
#
# return: -
#
# description:
# This functions stores the script parameters in global(!) vairables.
#
###############################################################################
function createjtagrespkey()
{
    JTAG_FILE="jtag_resp_key.txt"
    local JTAG_KEY_TEMP=$JTAG_KEY
    nerg=0x0
    i=0
    while [ $i -le 7 ]
    do
        zahl=`echo $JTAG_KEY | cut -b 1-2`
        zahl="0x"$zahl""
        nerg=$((nerg+zahl))
        JTAG_KEY=`echo ${JTAG_KEY:2}`
        i=$[i + 1]
    done
    #decimal
    var=`printf '%d\n' $nerg`
    #checksum
    echo "checksum is: "$var
    var2=$var"X"
    JTAG_KEY=$JTAG_KEY_TEMP
    echo $var2$JTAG_KEY > $JTAG_FILE
}


# main function
handleParameters "$@"
createjtagrespkey

echo $JTAG_FILE" is ready!"

exit 0
