#!/bin/bash

#declaration
chrlen=0
i=0
JTAG_KEY=0
JTAG_FILE="jtag_resp_key.txt"
nerg=0x0

#read JTAG responsible key
echo "Please enter the response key (7 Byte) (Little-Endian) and confirm it with enter\n"

#check if length is correct
while [ $chrlen != 14 ]
do
read action

chrlen=${#action}

if [ $chrlen != 14 ]; then
   echo "wrong length, try again ..."
fi
done

#check if values are hex values
if ! [[ $action =~ [a-f0-9]{$chrlen} ]]; then
    echo "No hex value, exit ..."
    exit
fi

JTAG_KEY=$action

#create checksum
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
JTAG_KEY=$action
echo $var2$JTAG_KEY > $JTAG_FILE
echo $JTAG_FILE" is ready!"
