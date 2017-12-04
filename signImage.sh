#!/bin/bash

# define constants

NORMAL='\033[0m'
LIGHT_GREEN='\033[1;32m'
LIGHT_RED='\033[0;31m'


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
    CPU_ARCH=$1
    OUTPUT_NAME=$2
    DEVTREE_LOAD_ADDR=$3
    IMAGE_PATH=$4
}

###############################################################################
# function: setCertNumberSigning()
#
# parameters: -
#
# return: -
#
# description:
# This function sets the numbers in the boot.csf-in file depending which
# created certificate should be used (is treated as '1')
#
###############################################################################

function setCertNumberSigning()
{
#    path=./cst-2.3.2/crts/
#    local quantity=`ls -d ${path}SRK*.pem | wc -l`
#    printf "Which certificate do you want to use for signing"
#    printf " (1-%u)?\b\n" "$quantity"
    local num=1
#    read num

#    if [[ ! $num =~ ^[0-9]+$ ]]; then
#	printf "Only integers are allowed!\b\n"
#	exit 1
#    fi
#
#    if [ "$num" -gt "$quantity" ] || [ "$num" -lt 1 ]; then
#	printf "Only values between 1 and %u! \b\n" "$quantity"
#	exit 1
#    fi

    local temp
    let "temp=$num - 1"
    sed -e "s/###INDEX###/$temp/" -e "s/###NUM###/$num/" \
    boot_raw_edited > boot_in.csf
}


###############################################################################
# function: getImageToBeSigned()
#
# parameters: -
#
# return: -
#
# description:
# Copies the specified image to the working directory and stores it's name in a
# global variable.
#
###############################################################################

function getImageToBeSigned()
{
    DIR=`dirname "$IMAGE_PATH"`

    if ! [ "$PWD" == "$DIR" ]; then
        cp "$IMAGE_PATH" .
    fi

    image=`basename "$IMAGE_PATH"`

    # since we take the u-boot.bin image, let's rename it to uboot.nb0

    if [ "$image" == "u-boot.bin" ]; then
	mv $image uboot.nb0
	image=uboot.nb0
    fi
}

###############################################################################
# function: getImageType()
#
# parameters: $1: image name
#
# return: -
#
#         LOAD_ADDRESS, IMAGE_NAME (global variable!!)
#
# description:
# Returns the image type.
#
###############################################################################

function getImageType()
{
    # check magic numbers in given image

    local MAGIC_NUMBER_E=`hexdump -n 4 -s 0x40 -e '"%x\n"' "$1"`
    local MAGIC_NUMBER_U=`hexdump -n 4 -s 0x3c -e '"%x\n"' "$1"`
    local MAGIC_NUMBER_M4=`hexdump -n 4 -s 0x0 -e '"%x\n"' "$1"`
    local MAGIC_NUMBER_N=`hexdump -n 4 -s 0x400 -e '"%x\n"' "$1"`
    local NBOOT_LOADADDR=`hexdump -n 4 -s 0x414 -e '"%x\n"' "$1"`
    local MAGIC_NUMBER_KERNEL=`hexdump -n 4 -s 0x0 -e '"%x\n"' "$1"`
    local MAGIC_NUMBER_DEVTREE=`hexdump -n 4 -s 0x0 -e '"%x\n"' "$1"`

    local UBOOT_NUMBER=`hexdump -n 4 -s 0x20 -e '"%x\n"' "$1"`
    local TEMP_VAR=$(( 0x$UBOOT_NUMBER & 0xFFFF0000 ))
    local UBOOT_CHECK_NUM=`printf "%x" "$TEMP_VAR"`

    if [ "$MAGIC_NUMBER_N" == "402000d1" ]; then
        LOAD_ADDRESS="$NBOOT_LOADADDR"
	if [ "$NBOOT_LOADADDR" == "907400" ]; then
	    if [ "$CPU_ARCH" == "SX" ]; then
	        IMAGE_NAME="nboot_sx"
	    elif [ "$CPU_ARCH" == "UL" ]; then
	        IMAGE_NAME="nboot_ul"
	    else
		IMAGE_NAME="nboot_imx"
	    fi
	elif [ "$NBOOT_LOADADDR" == "3f040400" ]; then
	    IMAGE_NAME="nboot_vyb"
	fi
    elif [ "$MAGIC_NUMBER_U" == "12345678" ]; then
        LOAD_ADDRESS="$UBOOT_CHECK_NUM"
	if [ "$UBOOT_CHECK_NUM" == "10100000" ]; then
	    IMAGE_NAME="uboot_imx"
	elif [ "$UBOOT_CHECK_NUM" == "80100000" ]; then
	    if [ "$CPU_ARCH" == "SX" ]; then
	        IMAGE_NAME="uboot_sx"
	    elif [ "$CPU_ARCH" == "UL" ]; then
	        IMAGE_NAME="uboot_ul"
	    else
		IMAGE_NAME="uboot_vyb"
	    fi
	fi
    elif [ "$MAGIC_NUMBER_KERNEL" == "56190527" ]; then
	local KERNEL_LOAD_ADDR=`hexdump -n 4 -s 0x14 -e '"%08x\n"' "$1"`
	# change endianess
	local temp_addr=`echo ${KERNEL_LOAD_ADDR:6:2}${KERNEL_LOAD_ADDR:4:2}\
${KERNEL_LOAD_ADDR:2:2}${KERNEL_LOAD_ADDR:0:2}`
	IMAGE_NAME="uImage"
	LOAD_ADDRESS="$temp_addr"
	echo "LOAD_ADDRESS ${LOAD_ADDRESS}"
    elif [ "$MAGIC_NUMBER_E" == "43454345" ] || \
         [ "$MAGIC_NUMBER_M4" == "4d344d34" ]; then
	printf "Not yet supported!\b\n"
	exit 1
    elif [ "$MAGIC_NUMBER_DEVTREE" == "edfe0dd0" ]; then
        IMAGE_NAME="devtree"
        if [ "$CPU_ARCH" == "SDQ" ]; then
            LOAD_ADDRESS=11000000
        else
            LOAD_ADDRESS=81000000
        fi
    else
	printf "Not an image file!\b\n"
	exit 1
    fi
}


###############################################################################
# function: makeSignedImage()
#
# parameters: $1: IMAGE_NAME
#
#
#
# return: -
#
# description:
# This function creates the signed image (by calling setSignedCSFfile()).
#
###############################################################################

function makeSignedImage()
{
    if [[ "$1" != *"nboot"* ]]; then
        local IVT_FILE=`echo "${1}_ivt.bin"`
	local IMAGE_IVT=`echo "${1}_ivt"`
	# append image to the created IVT file
        cat $IVT_FILE $image > $IMAGE_IVT
        rm $IVT_FILE
        mv $IMAGE_IVT $image
    fi

    setSignedCSFfile $1
}

###############################################################################
# function: setSignedCSFfile()
#
# parameters: $1: IMAGE_NAME
#
# return: -
#
# description:
# This function sets all the remaining wildcards in the "boot_in.csf"
# and runs the cst tool to generate a signed image. Warning, TARGET is a global
# variable!!
#
###############################################################################

function setSignedCSFfile()
{
    local ADDR=0x"$LOAD_ADDRESS"
    local IMAGE_SIZE=0x$BOOT_DATA_LENGTH
    local SIZE=$(stat -c %s "$image")
    SIZE=0x`printf "%08x" "$SIZE"`

    if [[ "$1" == *"nboot"* ]]; then
        local OFFSET=0x400
        local TRUNCATE_SIZE=`grep -a -o -b "##CSF##" "$image" | \
                             sed -e "s/:.*//"`
	local TEMP_SIZE=0x`printf "%x" "$TRUNCATE_SIZE"`
	let TEMP_SIZE="$TEMP_SIZE - 0x400"
	local SIZE=0x`printf "%x" "$TEMP_SIZE"`

	if [ "$CPU_ARCH" == "SX" ]; then
	    TARGET=nbootsx_signed.bin
	elif [ "$CPU_ARCH" == "UL" ]; then
	    TARGET=nbootul_signed.bin
	elif [ "$CPU_ARCH" == "SDQ" ]; then
	    TARGET=nbootimx6_signed.bin
	else
	    TARGET=nbootvyb_signed.bin
	fi

	local IMAGE_SIZE=0x10000

	if [ "$OUTPUT_NAME" == "nboot_for_key.bin" ]; then
	    if [ "$MASTER_KEY" == "z" ]; then
	        sed -e '15,20s/#//' boot_in.csf > boot_temp
	        sed -e '28,43s/#//' boot_temp > boot_in.csf
	    else
	        sed -e '15,17s/#//' boot_in.csf > boot_temp
	        cp boot_temp boot_in.csf
	    fi
	    rm boot_temp
	fi
    else
        local OFFSET=0x0
        if [[ "$1" == *"uboot"* ]]; then
            TARGET=`echo "${1}_signed.nb0"`
        elif [ "$1" == uImage ]; then
	    TARGET="${1}_${CPU_ARCH}_signed"
	else
	    TARGET="${image}_signed"
        fi
    fi

    sed -e "s/###ADDR###/$ADDR/" -e "s/###OFFSET###/$OFFSET/" \
        -e "s/###SIZE###/$SIZE/" -e "s/###BOOT###/$image/" \
        boot_in.csf > boot_in.csf_temp
    mv boot_in.csf_temp boot_in.csf

    # generate no output on stdout

    cst-2.3.2/linux64/cst --o csf.bin --i  boot_in.csf 1>/dev/null

    if [[ "$1" == *"nboot"* ]]; then
        truncate -s $TRUNCATE_SIZE $image
    fi

    if [ -n "$OUTPUT_NAME" ]; then
	TARGET="$OUTPUT_NAME"
    fi

    cat $image csf.bin > $TARGET
    rm csf.bin
    rm $image
    rm boot_in.csf
    objcopy -I binary -O binary --pad-to=$IMAGE_SIZE --gap-fill=0xFF $TARGET \
    $TARGET
}

###############################################################################
# function: createIVTHeader()
#
# parameters: $1: basename of given file
#             $2: variable IMAGE_NAME (internally name of file)
# return: -
#
# description:
# This function creates the IVT header (if necesarry) and adds it at the
# beginning of the image.
#
###############################################################################

function createIVTHeader()
{
    local IVT_HEADER=402000D1
    local IVT_TARGET=`echo "${2}_ivt.bin"`
    local SELF_POINTER="$LOAD_ADDRESS"
    let local BOOT_DATA="$LOAD_ADDRESS + 20"

    if [ "$2" == "uImage" ] || [ "$2" == "devtree" ]; then
	let local ENTRY_POINT="$LOAD_ADDRESS + 40"
    else
    	let local ENTRY_POINT="$BOOT_DATA"
    fi

    local ZEROS=00000000
    local CSF_ADDR=$(stat -c %s "$1")

    # round CSF_ADDR up to the next 0x10 boundary (left-adjusted)

    CSF_ADDR=$((($CSF_ADDR+15)/16))
    CSF_ADDR=$(($CSF_ADDR * 16))

    objcopy -I binary -O binary --pad-to=$CSF_ADDR --gap-fill=0xFF $1 $1

    if [ "$keylength" == "128" ]; then
	let CSF_ADDR="$CSF_ADDR + 0x48"
    elif [ "$keylength" == "192" ]; then
	let CSF_ADDR="$CSF_ADDR + 0x50"
    elif [ "$keylength" == "256" ]; then
	let CSF_ADDR="$CSF_ADDR + 0x58"
    fi

    local temp=`echo ${IVT_HEADER:6:2}${IVT_HEADER:4:2}${IVT_HEADER:2:2}\
${IVT_HEADER:0:2}`
    local out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`

    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final > $IVT_TARGET

    temp=`echo ${ENTRY_POINT:6:2}${ENTRY_POINT:4:2}${ENTRY_POINT:2:2}\
${ENTRY_POINT:0:2}`
    out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final >> $IVT_TARGET

    out=`echo -n -e $ZEROS | sed -e 's/.\{2\}/&\\\x/g'`
    temp=\\x$out
    local zeroes=${temp::-2}
    echo -n -e $zeroes >> $IVT_TARGET
    echo -n -e $zeroes >> $IVT_TARGET

    temp=`echo ${BOOT_DATA:6:2}${BOOT_DATA:4:2}${BOOT_DATA:2:2}\
${BOOT_DATA:0:2}`

    out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`

    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final >> $IVT_TARGET

    temp=`echo ${SELF_POINTER:6:2}${SELF_POINTER:4:2}${SELF_POINTER:2:2}\
${SELF_POINTER:0:2}`
    out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final >> $IVT_TARGET

    if [ "$2" == "uImage" ] || [ "$2" == "devtree" ]; then
	CSF_ADDR=`printf "%d "$(($CSF_ADDR-32))`
    fi

    CSF_ADDR=`printf "%08x" $CSF_ADDR`
    CSF_ADDR=`printf "%08x" $((0x$CSF_ADDR+0x$ENTRY_POINT))`

    temp=`echo ${CSF_ADDR:6:2}${CSF_ADDR:4:2}${CSF_ADDR:2:2}${CSF_ADDR:0:2}`
    out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final >> $IVT_TARGET


    out=`echo -n -e $ZEROS | sed -e 's/.\{2\}/&\\\x/g'`
    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final >> $IVT_TARGET

}

###############################################################################
# function: createBootDataHeader()
#
# parameters: $1: basename of given file
#             $2: variable IMAGE_NAME (internally name of file)
# return: -
#
# description:
# This function creates the BOOT DATA header (if necesarry) and adds it at the
# beginning of the image.
#
###############################################################################

function createBootDataHeader()
{
    local ZEROS=00000000
    local FF_PAD=FFFFFFFF
    local DATA_TARGET=`echo "${2}_boot_data.bin"`
    if [ "$2" == "uImage" ]; then
	local temp_addr=`echo -n -e $LOAD_ADDRESS | sed -e 's/.\{2\}/&\\\x/g'`
    else
        local temp_addr=`echo ${LOAD_ADDRESS:6:2}${LOAD_ADDRESS:4:2}\
${LOAD_ADDRESS:2:2}${LOAD_ADDRESS:0:2}`
        temp_addr=`echo -n -e $temp_addr | sed -e 's/.\{2\}/&\\\x/g'`
    fi

    runFakeCST "$1" "$2" "signed"

    local temp_length=`echo ${BOOT_DATA_LENGTH:6:2}${BOOT_DATA_LENGTH:4:2}\
${BOOT_DATA_LENGTH:2:2}${BOOT_DATA_LENGTH:0:2}`
    echo "temp_length = ${temp_length}"
    local out_zeros=`echo -n -e $ZEROS | sed -e 's/.\{2\}/&\\\x/g'`
    local out_ffpad=`echo -n -e $FF_PAD | sed -e 's/.\{2\}/&\\\x/g'`
    temp_length=`echo -n -e $temp_length | sed -e 's/.\{2\}/&\\\x/g'`

    local temp=\\x$temp_addr
    local final=${temp::-2}
    echo -n -e $final > $DATA_TARGET

    temp=\\x$temp_length
    final=${temp::-2}
    echo -n -e $final >> $DATA_TARGET

    temp=\\x$out_zeros
    final=${temp::-2}
    echo -n -e $final >> $DATA_TARGET

    temp=\\x$out_ffpad
    final=${temp::-2}
    echo -n -e $final >> $DATA_TARGET

    temp=\\x$out_ffpad
    final=${temp::-2}
    echo -n -e $final >> $DATA_TARGET

    temp=\\x$out_ffpad
    final=${temp::-2}
    echo -n -e $final >> $DATA_TARGET

    temp=\\x$out_ffpad
    final=${temp::-2}
    echo -n -e $final >> $DATA_TARGET

    temp=\\x$out_ffpad
    final=${temp::-2}
    echo -n -e $final >> $DATA_TARGET

    cat $DATA_TARGET $1 > temp.out
    mv temp.out $1
    rm $DATA_TARGET
}


###############################################################################
# function: runFakeCST()
#
# parameters: $1: image
#             $2: image type
#
#
# return:     BOOT_DATA_LENGTH (global variable!!)
#
#
# description:
# Runs the cst tool using fake options in order to create a temporary binary
# csf file. We need this binary file to calculate the exact image length
# (for the boot data header). The length is stored in BOOT_DATA_LENGTH
# (global variable!!).
#
###############################################################################

runFakeCST()
{
	case $2 in
	    *nboot*)
                BOOT_DATA_LENGTH=10000
	        BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
                ;;
            uboot_vyb)
            	BOOT_DATA_LENGTH=60000
	        BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
	        ;;
            *uboot*)
            	BOOT_DATA_LENGTH=80000
	        BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
	        ;;
            *)
	    sed -e "s/###ADDR###/0x$LOAD_ADDRESS/" -e "s/###OFFSET###/0x0/" \
	        -e "s/###SIZE###/0x10/" -e "s/###BOOT###/$image/" \
	        boot_in.csf > boot_in.csf_temp

	    # suppress output generated by the cst tool
	    cst-2.3.2/linux64/cst --o csf.bin --i boot_in.csf_temp 1>/dev/null

	    cat $image csf.bin > ${image}_fake
	    BOOT_DATA_LENGTH=$(stat -c %s "${image}_fake")
	    let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 1"

	    BOOT_DATA_LENGTH=$((($BOOT_DATA_LENGTH+15)/16))
	    BOOT_DATA_LENGTH=$(($BOOT_DATA_LENGTH * 16))
	    # add the 0x40 (64) Byte header (0x20 IVT, 0x20 BOOT_DATA)
	    let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 64"

	    BOOT_DATA_LENGTH=`printf "%08x" $BOOT_DATA_LENGTH`
	    rm ${image}_fake
	    rm boot_in.csf_temp
	esac
}


# main function
handleParameters "$@"
setCertNumberSigning
getImageToBeSigned
getImageType $image
case $IMAGE_NAME in
    *nboot*)
        makeSignedImage $IMAGE_NAME
        ;;
    *)
    	createBootDataHeader $image $IMAGE_NAME
	createIVTHeader $image $IMAGE_NAME
	makeSignedImage $IMAGE_NAME
	;;
esac

if [ "$?" == "0" ]; then
    printf "\n${LIGHT_GREEN}Signed image (%s) successfully generated.${NORMAL}
           \r" "$TARGET"
    exit 0
else
    printf "$\n{LIGHT_RED}Error, aborting...${NORMAL}\b\n"
    exit 1
fi
