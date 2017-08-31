#!/bin/bash

# define constants

NORMAL='\033[0m'
LIGHT_GREEN='\033[1;32m'
LIGHT_RED='\033[0;31m'


################################################################################
# function: handleParameters()
#
# parameters: all parameters given to the script
#
# return: -
#
# description:
# This functions stores the script parameters in global(!) vairables.
#
################################################################################

function handleParameters()
{
    CPU_ARCH=$1
    OUTPUT_NAME=$2
    DEVTREE_LOAD_ADDR=$3
    IMAGE_PATH=$4
    KEY_LENGTH=$5
}



################################################################################
# function: checkEncryptionTool()
#
# parameters: -
#
# return: -
#
#
# description:
# Checks if the cst tool is enabled for encryption or not.
#
################################################################################


function checkEncryptionTool()
{
    cd cst-2.3.2/linux64/
    if [ -f "cst_encrypt" ]; then
	cd ../../
    else
	cd ../code/back_end/src
	gcc -o cst_encrypt -I ../hdr -L ../../../linux64/lib *.c -lfrontend -lcrypto
	cp cst_encrypt ../../../linux64/
	cd ../../../../
    fi

}

################################################################################
# function: checkNBootForEncryption()
#
# parameters: -
#
# return: -
#
# description:
# Since there must not be an 'Unlock' command in the csf file when we want to
# generate the keys, wen need to make an seperat NBoot for this.
#
################################################################################


function checkNBootForEncryption()
{
    if [ ! -f ./nboot_for_key.bin ]; then
	sed -e "s/###INDEX###/0/" -e "s/###NUM###/1/" ./boot_raw_edited > boot_in.csf
	printf "Enter NBoot image path ${BOLD}(absolute address!)${NORMAL}\b\n"
	printf "\t${BOLD}This is required since we need to change settings in the${NOMRAL}\b\n"
	printf "\t${BOLD}Command Sequence File in order to generate the keys.${NORMAL}\b\n"
	read nboot_path
	./makeAction.sh --output=nboot_for_key.bin --cpu="$CPU_ARCH" --action=s --image-path="$nboot_path"
	exit 0
    fi
}

################################################################################
# function: setCertNumberEncrypting()
#
# parameters: -
#
# return: -
#
# description:
# This function sets the numbers in the boot.csf-in file depending which created
# certificate should be used (is treated as '1'!!).
#
################################################################################

function setCertNumberEncrypting()
{
#    local quantity=$(cat ./cst-2.3.2/keys/count_SRK.bak)
#    printf "Which certificate do you want to use for encrypting (1-%u)?\b\n" "$quantity"
#    local num
#    read num
#
#    if [[ ! $num =~ ^[0-9]+$ ]]; then
#	printf "Only integers are allowed!\b\n"
#	exit 1
#    fi
#
#    if [ "$num" -gt "$quantity" ] || [ "$num" -lt 1 ]; then
#	printf "Only values between 1 and %u! \b\n" "$quantity"
#	exit 1
#    fi

    # We set the value to '1'
    local num=1
    let "temp=$num - 1"

    sed -e "s/###INDEX###/$temp/" -e "s/###NUM###/$num/" ./boot_raw_edited > boot_in.csf
}


################################################################################
# function: getImageToBeEncrypted()
#
# parameters: -
#
# return: -
#
# description:
# Copies the specified image to the working directory and stores it's name in a
# global variable.
#
################################################################################


function getImageToBeEncrypted()
{
    DIR=`dirname "$IMAGE_PATH"`

    if ! [ "$PWD" == "$DIR" ]; then
        cp "$IMAGE_PATH" .
    fi

    image=$(basename "$IMAGE_PATH")

    # since we take the u-boot.bin image, let's rename it to uboot.nb0

    if [ "$image" == "u-boot.bin" ]; then
	mv $image uboot.nb0
	image=uboot.nb0
    fi

}


################################################################################
# function: getImageType()
#
# parameters: $1: image name
#
# return: 1: NBoot IMX6, NBoot IMX6Q, NBoot IMX6SX
#         2: NBoot Vybrid
#         3: UBoot IMX
#         4: UBoot Vybrid
#         5: uImage
#         6: Devtree
#         7: NBoot IMX6UL
#         8: UBoot UL
#
#         KERNEL_LOAD_ADDR (global variable!!)
#
# description:
# Returns the image type.
#
################################################################################

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
	if [ "$NBOOT_LOADADDR" == "907400" ]; then
	    if [ "$CPU_ARCH" == "UL" ]; then
		return 7                          # NBoot UL
	    else
		return 1                              # NBoot IMX6
	    fi
	elif [ "$NBOOT_LOADADDR" == "3f040400" ]; then
	    echo "Not supported yet!"
	    rm "$1"
	    exit 1                          # NBoot Vybrid
	fi
    elif [ "$MAGIC_NUMBER_U" == "12345678" ]; then
	if [ "$UBOOT_CHECK_NUM" == "10100000" ]; then
	    return 3                              # UBoot IMX6
	elif [ "$UBOOT_CHECK_NUM" == "80100000" ]; then
	    if [ "$CPU_ARCH" == "UL" ]; then
		return 8                          # UBoot UL
	    else
		return 4                              # UBoot Vybrid/UBoot IMX6UL/SX
	    fi
	fi
    elif [ "$MAGIC_NUMBER_KERNEL" == "56190527" ]; then
	KERNEL_LOAD_ADDR=`hexdump -n 4 -s 0x14 -e '"%08x\n"' "$1"`

	# change endianess

	local temp_addr=`echo ${KERNEL_LOAD_ADDR:6:2}${KERNEL_LOAD_ADDR:4:2}${KERNEL_LOAD_ADDR:2:2}${KERNEL_LOAD_ADDR:0:2}`
	KERNEL_LOAD_ADDR="$temp_addr"                     # !! change global variable KERNEL_LOAD_ADDR !!
	return 5
    elif [ "$MAGIC_NUMBER_E" == "43454345" ] || [ "$MAGIC_NUMBER_M4" == "4d344d34" ]; then
	printf "Not yet supported!\b\n"
	exit 1
    elif [ "$MAGIC_NUMBER_DEVTREE" == "edfe0dd0" ]; then
	return 6
    else
	printf "Not an image file!\b\n"
	exit 1
    fi

}


################################################################################
# function: makeEncryptedImage()
#
# parameters: $1: image type (NBoot IMX/UBoot IMX)
#
# return: -
#
# description:
# This function creates the encrypted (and also signed!) image
# (by calling setEncryptedCSFFile()).
#
################################################################################

function makeEncryptedImage()
{
    if [ "$1" == "nboot_imx" ]; then
	setEncryptedCSFFile nboot_imx
	return
    elif [ "$1" == "nboot_ul" ]; then
	setEncryptedCSFFile nboot_ul
	return
    elif [ "$1" == "uboot_imx" ]; then

	local IVT_FILE=uboot_imx_ivt.bin
	local IMAGE_IVT=uboot_imx_ivt

	cat $IVT_FILE $image > $IMAGE_IVT
	rm $IVT_FILE
	mv $IMAGE_IVT $image

	setEncryptedCSFFile uboot_imx
    elif [ "$1" == "uboot_ul" ]; then

	local IVT_FILE=uboot_ul_ivt.bin
	local IMAGE_IVT=uboot_ul_ivt

	cat $IVT_FILE $image > $IMAGE_IVT
	rm $IVT_FILE
	mv $IMAGE_IVT $image

	setEncryptedCSFFile uboot_ul
    elif [ "$1" == "uImage" ]; then
	local IVT_FILE=uImage_ivt.bin
	local IMAGE_IVT=uImage_ivt

	cat $IVT_FILE $image > $IMAGE_IVT
	rm $IVT_FILE
	mv $IMAGE_IVT $image

	setEncryptedCSFFile uImage
    elif [ "$1" == "devtree" ]; then
	local IVT_FILE=devtree_ivt.bin
	local IMAGE_IVT=devtree_ivt

	cat $IVT_FILE $image > $IMAGE_IVT
	rm $IVT_FILE
	mv $IMAGE_IVT $image
	setEncryptedCSFFile devtree
    fi

}


################################################################################
# function: setEncryptedCSFFile()
#
# parameters: $1: image type (NBoot IMX/NBoot Vybrid/UBoot IMX/ UBoot Vybrid)
#
# return: -
#
# description:
# This function set all the remaining wildcards in the "boot_in.csf"
# and runs the cst_encrypt tool to genarate a signed and encpted image.
#
################################################################################

function setEncryptedCSFFile()
{
    cp boot_in.csf boot_in.csf_temp
    if [ "$1" == "nboot_imx" ] || [ "$1" == "nboot_ul" ]; then
	local ADDR=0x00907400
	local ADDR_DEC=0x00907500
	local OFFSET_ENC=0x500
	local SIZE=0x100
	local OFFSET=0x400
	local TRUNCATE_SIZE=`grep -a -o -b "##CSF##" "$image" | sed -e "s/:.*//"`
	local KEY_ADDR=0x`printf "%08x" $(($TRUNCATE_SIZE+0x907000))`
	if [ "$KEY_LENGTH" == "128" ]; then
	    local CSF_ADDR_TEMP="$[KEY_ADDR + 0x48]"      # 72 Bytes
	elif [ "$KEY_LENGTH" == "192" ]; then
	    local CSF_ADDR_TEMP="$[KEY_ADDR + 0x50]"      # 80 Bytes
	elif [ "$KEY_LENGTH" == "256" ]; then
	    local CSF_ADDR_TEMP="$[KEY_ADDR + 0x58]"      # 88 Bytes
	fi

	local SIZE_DEC="$[TRUNCATE_SIZE -0x500]"
	local CSF_ADDR=`printf "%08x" "$CSF_ADDR_TEMP"`
	local IMAGE_SIZE=0x10000

	if [ "$1" == "nboot_imx" ]; then
	    TARGET=nbootimx6_enc.bin
	elif [ "$1" == "nboot_ul" ]; then
	    TARGET=nbootimx6ul_enc.bin
	fi

	SIZE_DEC=`echo $(( SIZE_DEC / 16 ))`       # make SIZE_DEK a multiple of 16
	SIZE_DEC=`echo $(( SIZE_DEC * 16 ))`
	SIZE_DEC=0x`printf "%x" "$SIZE_DEC"`

	sed -e "s/###ADDR###/$ADDR/" -e "s/###OFFSET###/$OFFSET/" -e "s/###SIZE###/$SIZE/" -e "s/###BOOT###/$image/" -e "s/###length###/$KEY_LENGTH/" -e "s/###KEY_ADDR###/$KEY_ADDR/" -e "s/###ADDR_DEC###/$ADDR_DEC/" -e "s/###OFFSET_ENC###/$OFFSET_ENC/" -e "s/###SIZE_DEC###/$SIZE_DEC/"  boot_in.csf > boot_in.csf_temp
	sed -e '18,20s/#//' boot_in.csf_temp > temp.csf
	sed -e '28,$s/#//' temp.csf > boot_in.csf
	rm temp.csf
	rm boot_in.csf_temp
	local temp=`echo ${CSF_ADDR:6:2}${CSF_ADDR:4:2}${CSF_ADDR:2:2}${CSF_ADDR:0:2}`
	local out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
	temp=\\x$out
	out=${temp::-2}
	printf $out | dd conv=notrunc status=none of=$image bs=1 seek=$((0x418))
	truncate -s $TRUNCATE_SIZE $image
    elif [ "$1" == "uboot_imx" ]; then

	local ADDR=0x10100000
	local OFFSET=0x0
	local SIZE=0x100
	local SIZE_DEC=$(stat -c %s "$image")
	TARGET=uboot_enc.nb0
	local IMAGE_SIZE=0x80000
	local ADDR_DEC=0x10100100
	local OFFSET_ENC=0x100
	local KEY_ADDR=0x`printf "%08x" $(($SIZE_DEC+$ADDR))`
	SIZE_DEC=0x`printf "%x" $(($SIZE_DEC-$SIZE))`    # length minus 48 Bytes are signed
	SIZE_DEC=`echo $(( SIZE_DEC / 16 ))`       # make SIZE_DEK a multiple of 16
	SIZE_DEC=`echo $(( SIZE_DEC * 16 ))`
	SIZE_DEC=0x`printf "%x" "$SIZE_DEC"`

	sed -e "s/###ADDR###/$ADDR/" -e "s/###OFFSET###/$OFFSET/" -e "s/###SIZE###/$SIZE/" -e "s/###BOOT###/$image/" -e "s/###length###/$KEY_LENGTH/" -e "s/###KEY_ADDR###/$KEY_ADDR/" -e "s/###ADDR_DEC###/$ADDR_DEC/" -e "s/###OFFSET_ENC###/$OFFSET_ENC/" -e "s/###SIZE_DEC###/$SIZE_DEC/"  boot_in.csf > boot_in.csf_temp
	sed -e '44,$s/#//' boot_in.csf_temp > boot_in.csf
	rm boot_in.csf_temp

    elif [ "$1" == "uboot_ul" ]; then

	local ADDR=0x80100000
	local OFFSET=0x0
	local SIZE=0x100
	local SIZE_DEC=$(stat -c %s "$image")
	TARGET=ubootul_enc.nb0
	local IMAGE_SIZE=0x80000
	local ADDR_DEC=0x80100100
	local OFFSET_ENC=0x100
	local KEY_ADDR=0x`printf "%08x" $(($SIZE_DEC+$ADDR))`
	SIZE_DEC=0x`printf "%x" $(($SIZE_DEC-$SIZE))`    # length minus 48 Bytes are signed
	SIZE_DEC=`echo $(( SIZE_DEC / 16 ))`       # make SIZE_DEK a multiple of 16
	SIZE_DEC=`echo $(( SIZE_DEC * 16 ))`
	SIZE_DEC=0x`printf "%x" "$SIZE_DEC"`

	sed -e "s/###ADDR###/$ADDR/" -e "s/###OFFSET###/$OFFSET/" -e "s/###SIZE###/$SIZE/" -e "s/###BOOT###/$image/" -e "s/###length###/$KEY_LENGTH/" -e "s/###KEY_ADDR###/$KEY_ADDR/" -e "s/###ADDR_DEC###/$ADDR_DEC/" -e "s/###OFFSET_ENC###/$OFFSET_ENC/" -e "s/###SIZE_DEC###/$SIZE_DEC/"  boot_in.csf > boot_in.csf_temp
	sed -e '44,$s/#//' boot_in.csf_temp > boot_in.csf
	rm boot_in.csf_temp

    elif [ "$1" == "uImage" ]; then

	local ADDR=0x$KERNEL_LOAD_ADDR
	local OFFSET=0x0
	local SIZE=0x100
	local ADDR_DEC=$(($ADDR + $SIZE))
	ADDR_DEC=`printf "%08x" "$ADDR_DEC"`
	local SIZE_DEC=$(stat -c %s "$image")
	local KEY_ADDR=0x`printf "%08x" $(($SIZE_DEC+$ADDR))`
	local OFFSET_ENC=$SIZE
	OFFSET_ENC=0x100
	let SIZE_DEC="$SIZE_DEC - 1 "
	SIZE=0x`printf "%08x" "$SIZE"`
	SIZE_DEC=0x`printf "%x" $(($SIZE_DEC-$SIZE))`    # length minus 48 Bytes are signed
	SIZE_DEC=`echo $(( SIZE_DEC / 16 ))`       # make SIZE_DEK a multiple of 16
	SIZE_DEC=`echo $(( SIZE_DEC * 16 ))`
	SIZE_DEC=0x`printf "%x" "$SIZE_DEC"`
	TARGET=uImage_enc
	local IMAGE_SIZE=0x$BOOT_DATA_LENGTH
	sed -e "s/###ADDR###/$ADDR/" -e "s/###OFFSET###/$OFFSET/" -e "s/###SIZE###/$SIZE/" -e "s/###BOOT###/$image/" -e "s/###length###/$KEY_LENGTH/" -e "s/###KEY_ADDR###/$KEY_ADDR/" -e "s/###ADDR_DEC###/0x$ADDR_DEC/" -e "s/###OFFSET_ENC###/$OFFSET_ENC/" -e "s/###SIZE_DEC###/$SIZE_DEC/"  boot_in.csf > boot_in.csf_temp
	sed -e '44,$s/#//' boot_in.csf_temp > boot_in.csf
	rm boot_in.csf_temp
    elif [ "$1" == "devtree" ]; then
	local ADDR=0x$DEVTREE_LOAD_ADDR
	local OFFSET=0x0
	local SIZE=0x100
	local ADDR_DEC=$(($ADDR + $SIZE))
	ADDR_DEC=`printf "%08x" "$ADDR_DEC"`
	local SIZE_DEC=$(stat -c %s "$image")
	local KEY_ADDR=0x`printf "%08x" $(($SIZE_DEC+$ADDR))`
	local OFFSET_ENC=$SIZE
	OFFSET_ENC=0x100
	let SIZE_DEC="$SIZE_DEC - 1 "
	SIZE=0x`printf "%08x" "$SIZE"`
	SIZE_DEC=0x`printf "%x" $(($SIZE_DEC-$SIZE))`    # length minus 48 Bytes are signed
	SIZE_DEC=`echo $(( SIZE_DEC / 16 ))`       # make SIZE_DEK a multiple of 16
	SIZE_DEC=`echo $(( SIZE_DEC * 16 ))`
	SIZE_DEC=0x`printf "%x" "$SIZE_DEC"`
	TARGET=${image}_enc
	local IMAGE_SIZE=0x$BOOT_DATA_LENGTH

	sed -e "s/###ADDR###/$ADDR/" -e "s/###OFFSET###/$OFFSET/" -e "s/###SIZE###/$SIZE/" -e "s/###BOOT###/$image/" -e "s/###length###/$KEY_LENGTH/" -e "s/###KEY_ADDR###/$KEY_ADDR/" -e "s/###ADDR_DEC###/0x$ADDR_DEC/" -e "s/###OFFSET_ENC###/$OFFSET_ENC/" -e "s/###SIZE_DEC###/$SIZE_DEC/"  boot_in.csf > boot_in.csf_temp
	sed -e '44,$s/#//' boot_in.csf_temp > boot_in.csf
	rm boot_in.csf_temp
    fi

    cst-2.3.2/linux64/cst_encrypt --o csf.bin --i  boot_in.csf 1>/dev/null

    if [ "$?" != "0" ]; then
	success=false
    fi
    cp dek.bin /tftpboot
    getDekBlob $KEY_LENGTH

    if [ -n "$OUTPUT_NAME" ]; then
	TARGET="$OUTPUT_NAME"
    fi

    cat $image dek_blob.bin > $TARGET-temp
    cat $TARGET-temp csf.bin > $TARGET
    rm $TARGET-temp
    rm csf.bin
    rm dek_blob.bin
    rm dek.bin
    rm $image
    rm boot_in.csf
    objcopy -I binary -O binary --pad-to=$IMAGE_SIZE --gap-fill=0xFF $TARGET $TARGET

}


################################################################################
# function: getDekBlob()
#
# parameters: $1: key length (128/192/256)
#
# return: -
#
# description:
# Generates the dek_blob.bin from given key (created on the board).
#
################################################################################


function getDekBlob()
{
    printf "Insert key\b\n"
    local blob
    read blob
    echo $blob > dek_blob.txt
    local append=$(cat dek_blob.txt)
    local size_key=`stat -c %s dek_blob.txt`
    let "EOS=$size_key / 2"
    echo -n "\x" > test.txt
    echo -n ${append:0:2} >> test.txt
    append=`echo ${append:2}`
    for (( c=1; c<$EOS; c++ ))
    do
	echo -n "\x" >> test.txt
	echo -n ${append:0:2} >> test.txt
	append=`echo ${append:2}`
    done
    local str="$(cat test.txt)"
    rm test.txt
    rm dek_blob.txt
    printf $str > dek_blob.bin
}

################################################################################
# function: createIVTHeader()
#
# parameters: $1: image name
#             $2: image type (uboot_imx/uboot_vyb/uboot_ul/devtree/uImage)
# return: -
#
# description:
# This function creates the IVT header (if necesarry) and adds it at the beginning of
# the image.
#
################################################################################

function createIVTHeader()
{
    local IVT_HEADER=402000D1
    if [ "$2" == "uboot_imx" ];then

	local ENTRY_POINT=10100020
	local SELF_POINTER=10100000
	local BOOT_DATA=10100020
	local IVT_TARGET=uboot_imx_ivt.bin

    elif [ "$2" == "uboot_vyb" ] || [ "$2" == "uboot_ul" ]; then

	local ENTRY_POINT=80100020
	local SELF_POINTER=80100000
	local BOOT_DATA=80100020
	if [ "$CPU_ARCH" == "VYB" ]; then
	    local IVT_TARGET=uboot_vyb_ivt.bin
	else
	    local IVT_TARGET=uboot_ul_ivt.bin
	fi
    elif [ "$2" == "uImage" ]; then

	local IVT_TARGET=uImage_ivt.bin

	let local ENTRY_POINT="$KERNEL_LOAD_ADDR + 40"
	local SELF_POINTER="$KERNEL_LOAD_ADDR"
	let local BOOT_DATA="$KERNEL_LOAD_ADDR + 20"
    elif [ "$2" == "devtree" ]; then
	temp_addr=$DEVTREE_LOAD_ADDR
	local IVT_TARGET=devtree_ivt.bin
	let local ENTRY_POINT="$DEVTREE_LOAD_ADDR + 40"
	local SELF_POINTER="$DEVTREE_LOAD_ADDR"
	let local BOOT_DATA="$DEVTREE_LOAD_ADDR + 20"
    fi

    local ZEROS=00000000

    local CSF_ADDR=$(stat -c %s "$1")

    # round CSF_ADDR up to the next 0x10 boundary (left-adjusted)

    CSF_ADDR=$((($CSF_ADDR+15)/16))
    CSF_ADDR=$(($CSF_ADDR * 16))

    objcopy -I binary -O binary --pad-to=$CSF_ADDR --gap-fill=0xFF $1 $1

    if [ "$KEY_LENGTH" == "128" ]; then
	let CSF_ADDR="$CSF_ADDR + 0x48"
    elif [ "$KEY_LENGTH" == "192" ]; then
	let CSF_ADDR="$CSF_ADDR + 0x50"
    elif [ "$KEY_LENGTH" == "256" ]; then
	let CSF_ADDR="$CSF_ADDR + 0x58"
    fi

    local temp=`echo ${IVT_HEADER:6:2}${IVT_HEADER:4:2}${IVT_HEADER:2:2}${IVT_HEADER:0:2}`
    local out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`

    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final > $IVT_TARGET

    temp=`echo ${ENTRY_POINT:6:2}${ENTRY_POINT:4:2}${ENTRY_POINT:2:2}${ENTRY_POINT:0:2}`
    out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final >> $IVT_TARGET

    out=`echo -n -e $ZEROS | sed -e 's/.\{2\}/&\\\x/g'`
    temp=\\x$out
    local zeroes=${temp::-2}
    echo -n -e $zeroes >> $IVT_TARGET
    echo -n -e $zeroes >> $IVT_TARGET

    temp=`echo ${BOOT_DATA:6:2}${BOOT_DATA:4:2}${BOOT_DATA:2:2}${BOOT_DATA:0:2}`

    out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`

    temp=\\x$out
    final=${temp::-2}
    echo -n -e $final >> $IVT_TARGET

    temp=`echo ${SELF_POINTER:6:2}${SELF_POINTER:4:2}${SELF_POINTER:2:2}${SELF_POINTER:0:2}`
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

################################################################################
# function: createBootDataHeader()
#
# parameters: $1: image name
#             $2: image type (uboot_imx/uboot_vyb)
# return: -
#
# description:
# This function creates the BOOT DATA header (if necesarry) and adds it at the beginning of
# the image.
#
################################################################################

function createBootDataHeader()
{
    local ZEROS=00000000
    local FF_PAD=FFFFFFFF
    if [ "$2" == "uImage" ]; then

	local DATA_TARGET=uImage_boot_data.bin
	local temp_addr=`echo -n -e $KERNEL_LOAD_ADDR | sed -e 's/.\{2\}/&\\\x/g'`
	runFakeCST "$1" "uImage"
    elif [ "$2" == "uboot_imx" ]; then
	local DATA_TARGET=uboot_imx_boot_data.bin
	local temp_addr=10100000
	temp_addr=`echo ${temp_addr:6:2}${temp_addr:4:2}${temp_addr:2:2}${temp_addr:0:2}`
	temp_addr=`echo -n -e $temp_addr | sed -e 's/.\{2\}/&\\\x/g'`
	runFakeCST "$1" "uboot_imx"
    elif [ "$2" == "uboot_vyb" ]; then
	if [ "$CPU_ARCH" == "VYB" ]; then
	    local DATA_TARGET=uboot_vyb_boot_data.bin
	else
	    local DATA_TARGET=uboot_ul_boot_data.bin
	fi
	local temp_addr=80100000
	temp_addr=`echo ${temp_addr:6:2}${temp_addr:4:2}${temp_addr:2:2}${temp_addr:0:2}`
	temp_addr=`echo -n -e $temp_addr | sed -e 's/.\{2\}/&\\\x/g'`
	runFakeCST "$1" "uboot_vyb"
    elif [ "$2" == "uboot_ul" ]; then
	local DATA_TARGET=uboot_vyb_boot_data.bin
	local temp_addr=80100000
	temp_addr=`echo ${temp_addr:6:2}${temp_addr:4:2}${temp_addr:2:2}${temp_addr:0:2}`
	temp_addr=`echo -n -e $temp_addr | sed -e 's/.\{2\}/&\\\x/g'`
	runFakeCST "$1" "uboot_ul"
    elif [ "$2" == "devtree" ]; then
	local DATA_TARGET=devtree_boot_data.bin
	local temp_addr=`echo ${DEVTREE_LOAD_ADDR:6:2}${DEVTREE_LOAD_ADDR:4:2}${DEVTREE_LOAD_ADDR:2:2}${DEVTREE_LOAD_ADDR:0:2}`
	temp_addr=`echo -n -e $temp_addr | sed -e 's/.\{2\}/&\\\x/g'`
	runFakeCST "$1" "devtree"                     # create temporary, binary csf file.
    fi
    local temp_length=`echo ${BOOT_DATA_LENGTH:6:2}${BOOT_DATA_LENGTH:4:2}${BOOT_DATA_LENGTH:2:2}${BOOT_DATA_LENGTH:0:2}`
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


################################################################################
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
# (for the boot data header). The length is stored in BOOT_DATA_LENGTH (global variable!!).
#
################################################################################

runFakeCST()
{
    cp $image ${image}-bak
	if [ "$2" == "uboot_imx" ]; then
	    BOOT_DATA_LENGTH=80000
	    BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
	elif [ "$2" == "uboot_vyb" ]; then
	    BOOT_DATA_LENGTH=60000
	    BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
	elif [ "$2" == "uboot_ul" ]; then
	    BOOT_DATA_LENGTH=80000
	    BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
	elif [ "$2" == "nboot_imx" ]; then
	    BOOT_DATA_LENGTH=10000
	    BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
	elif [ "$2" == "nboot_vyb" ]; then
	    BOOT_DATA_LENGTH=10000
	    BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
	elif [ "$2" == "uImage" ]; then

	    sed -e "s/###ADDR###/0x$KERNEL_LOAD_ADDR/" -e "s/###OFFSET###/0x0/" -e "s/###SIZE###/0x10/" -e "s/###BOOT###/$image/" -e "s/###length###/$KEY_LENGTH/" -e "s/###KEY_ADDR###/0x$KERNEL_LOAD_ADDR/" -e "s/###ADDR_DEC###/0x$KERNEL_LOAD_ADDR/" -e "s/###OFFSET_ENC###/0x100/" -e "s/###SIZE_DEC###/0x10/"  boot_in.csf > boot_in.csf_temp
	    sed -e '44,$s/#//' boot_in.csf_temp > boot_fake.csf
	    cp $image ${image}-bak

	    # suppress output generated by the cst tool
	    cst-2.3.2/linux64/cst_encrypt --o csf.bin --i boot_fake.csf 1>/dev/null

	    if [ "$?" != "0" ]; then
		success=false
	    fi

	    cat $image csf.bin > ${image}_fake
	    BOOT_DATA_LENGTH=$(stat -c %s "${image}_fake")
	    let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 1"

	    BOOT_DATA_LENGTH=$((($BOOT_DATA_LENGTH+15)/16))
	    BOOT_DATA_LENGTH=$(($BOOT_DATA_LENGTH * 16))
	    let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 64"        # add the 0x40 (64) Byte header (0x20 IVT, 0x20 BOOT_DATA)

	    if [ "$KEY_LENGTH" == "128" ]; then                   # add key length to size
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x48"
	    elif [ "$KEY_LENGTH" == "192" ]; then
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x50"
	    elif [ "$KEY_LENGTH" == "256" ]; then
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x58"
	    fi

	    BOOT_DATA_LENGTH=`printf "%08x" $BOOT_DATA_LENGTH`
	    rm ${image}_fake
	    rm boot_fake.csf
	elif [ "$2" == "devtree" ]; then

	    sed -e "s/###ADDR###/0x$DEVTREE_LOAD_ADDR/" -e "s/###OFFSET###/0x0/" -e "s/###SIZE###/0x10/" -e "s/###BOOT###/$image/" -e "s/###length###/$KEY_LENGTH/" -e "s/###KEY_ADDR###/0x$DEVTREE_LOAD_ADDR/" -e "s/###ADDR_DEC###/0x$DEVTREE_LOAD_ADDR/" -e "s/###OFFSET_ENC###/0x100/" -e "s/###SIZE_DEC###/0x10/"  boot_in.csf > boot_in.csf_temp
	    sed -e '44,$s/#//' boot_in.csf_temp > boot_fake.csf

	    # suppress output generated by the cst tool
	    cst-2.3.2/linux64/cst_encrypt --o csf.bin --i  boot_fake.csf 1>/dev/null

	    if [ "$?" != "0" ]; then
		success=false
	    fi

	    cat $image csf.bin > ${image}_fake
	    BOOT_DATA_LENGTH=$(stat -c %s "${image}_fake")
	    let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 1"

	    # round length according to CSF (see 'createIVTHeader')
	    BOOT_DATA_LENGTH=$((($BOOT_DATA_LENGTH+15)/16))
	    BOOT_DATA_LENGTH=$(($BOOT_DATA_LENGTH * 16))
	    let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 64"        # add the 0x40 Byte header (0x20 IVT, 0x20 BOOT_DATA)

	    if [ "$KEY_LENGTH" == "128" ]; then                   # add key length to size
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x48"
	    elif [ "$KEY_LENGTH" == "192" ]; then
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x50"
	    elif [ "$KEY_LENGTH" == "256" ]; then
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x58"
	    fi

	    BOOT_DATA_LENGTH=`printf "%08x" $BOOT_DATA_LENGTH`
	    rm ${image}_fake
	    rm boot_fake.csf
	fi

	mv ${image}-bak $image
}


# main function

handleParameters "$@"
checkEncryptionTool
checkNBootForEncryption
setCertNumberEncrypting
getImageToBeEncrypted
getImageType $image
case $? in
    1 )
	echo NBoot IMX
	makeEncryptedImage nboot_imx
	if [ "$?" == "0" ]; then
	    printf "${LIGHT_GREEN}Encrypted image (%s) successfully generated.${NORMAL}\b\n" "$TARGET"
	else
	    printf "${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
	fi
	;;
    3 )
	echo UBoot IMX
	createBootDataHeader $image uboot_imx enc
	createIVTHeader $image uboot_imx
	makeEncryptedImage uboot_imx
	if [ "$?" == "0" ]; then
	    printf "${LIGHT_GREEN}Encrypted image (%s) successfully generated.${NORMAL}\b\n" "$TARGET"
	else
	    printf "${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
	fi
	;;
    5 )
	echo uImage
	createBootDataHeader $image uImage enc
	createIVTHeader $image uImage
	makeEncryptedImage uImage
	if [ "$?" == "0" ]; then
	    printf "${LIGHT_GREEN}Encrypted uImage image (%s) successfully generated.${NORMAL}\b\n" "$TARGET"
	else
	    printf "${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
	fi
	;;
    6 )
	echo Device Tree
	createBootDataHeader $image devtree enc
	createIVTHeader $image devtree
	makeEncryptedImage devtree
	if [ "$?" == "0" ]; then
	    printf "${LIGHT_GREEN}Encrypted image (%s) successfully generated.${NORMAL}\b\n" "$TARGET"
	else
	    printf "${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
	fi
	;;
    7 )

	makeEncryptedImage nboot_ul
	if [ "$?" == "0" ]; then
	    printf "${LIGHT_GREEN}Encrypted image (%s) successfully generated.${NORMAL}\b\n" "$TARGET"
	else
	    printf "${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
	fi
	;;
    8 )
	createBootDataHeader $image uboot_ul enc
	createIVTHeader $image uboot_ul
	makeEncryptedImage uboot_ul
	if [ "$?" == "0" ]; then
	    printf "${LIGHT_GREEN}Encrypted image (%s) successfully generated.${NORMAL}\b\n" "$TARGET"
	else
	    printf "${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
	fi
	;;
    * )
	printf "${LIGHT_RED}Can not find a supported image for encryption!${NORMAL}\b\n"
	rm $image
	rm boot_in.csf
	success=false
	;;
esac


if [ "$success" == "false" ]; then
    printf "Error, image couldn't be generated!\b\n"
    exit 1
fi

exit 0
