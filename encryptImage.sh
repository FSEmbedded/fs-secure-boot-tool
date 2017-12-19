#!/bin/bash

# define constants

NORMAL='\033[0m'
LIGHT_GREEN='\033[1;32m'
LIGHT_RED='\033[0;31m'


###############################################################################
# function: handleParameters()
#
# parameters: all parameters given to the script
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
    CUSTOM_LOAD_ADDRESS=$3
    IMAGE_PATH=$4
    KEY_LENGTH=$5
    MASTER_KEY=$6
    CHECK_NBOOT_FOR_KEYS=$7
}


###############################################################################
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
###############################################################################
function checkEncryptionTool()
{
    cd cst-2.3.2/linux64/
    if [ -f "cst_encrypt" ]; then
	cd ../../
    else
	cd ../code/back_end/src
	gcc -o cst_encrypt -I ../hdr -L ../../../linux64/lib *.c -lfrontend \
	-lcrypto
	cp cst_encrypt ../../../linux64/
	cd ../../../../
    fi

}


###############################################################################
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
###############################################################################
function checkNBootForEncryption()
{
    local filename="nboot_${CPU_ARCH}_for_key_${MASTER_KEY}.bin"
    if [ ! -f ${filename} ]; then
	sed -e "s/###INDEX###/0/" -e "s/###NUM###/1/" ./boot_raw_edited > \
	boot_in.csf
	printf "Enter NBoot image path (absolute address!)\b\n"
	printf "\tThis is required since we need to change settings in
	the Command Sequence File in order to generate the keys.\b\n"
	read nboot_path
	./makeAction.sh --output=nboot_for_key.bin --cpu="$CPU_ARCH" \
	--action=s --image-path="$nboot_path" --master-key="$MASTER_KEY"
	exit 1
    fi
}


###############################################################################
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
###############################################################################
function setCertNumberEncrypting()
{
#    local quantity=$(cat ./cst-2.3.2/keys/count_SRK.bak)
#    printf "Which certificate do you want to use for encrypting (1-%u)?\b\n"
#    "$quantity"
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

    sed -e "s/###INDEX###/$temp/" -e "s/###NUM###/$num/" ./boot_raw_edited > \
    boot_in.csf
}


###############################################################################
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
###############################################################################
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
        IMAGE_NAME="nboot_${CPU_ARCH}"
    elif [ "$MAGIC_NUMBER_U" == "12345678" ]; then
        LOAD_ADDRESS="$UBOOT_CHECK_NUM"
        IMAGE_NAME="uboot_${CPU_ARCH}"
    elif [ "$MAGIC_NUMBER_KERNEL" == "56190527" ]; then
	local KERNEL_LOAD_ADDR=`hexdump -n 4 -s 0x14 -e '"%08x\n"' "$1"`
	# change endianess
	local temp_addr=`echo ${KERNEL_LOAD_ADDR:6:2}${KERNEL_LOAD_ADDR:4:2}\
${KERNEL_LOAD_ADDR:2:2}${KERNEL_LOAD_ADDR:0:2}`
	LOAD_ADDRESS="$temp_addr"
	IMAGE_NAME="uImage_${CPU_ARCH}"
    elif [ "$MAGIC_NUMBER_DEVTREE" == "edfe0dd0" ]; then
        if [ "$CPU_ARCH" == "sdq" ]; then
            LOAD_ADDRESS=11000000
        else
            LOAD_ADDRESS=81000000
        fi
        IMAGE_NAME="devtree"
    elif [ "$MAGIC_NUMBER_E" == "43454345" ] || \
         [ "$MAGIC_NUMBER_M4" == "4d344d34" ]; then
	printf "Not yet supported!\b\n"
	exit 1
    else
	printf "Not an image file!\b\n"
	exit 1
    fi

    if [ -n "$CUSTOM_LOAD_ADDRESS" ]; then
        LOAD_ADDRESS=$CUSTOM_LOAD_ADDRESS
    fi
}

###############################################################################
# function: makeEncryptedImage()
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
function makeEncryptedImage()
{
    if [[ "$1" != *"nboot"* ]]; then
        local IVT_FILE=`echo "${1}_ivt.bin"`
	local IMAGE_IVT=`echo "${1}_ivt"`
	# append image to the created IVT file
        cat $IVT_FILE $image > $IMAGE_IVT
        rm $IVT_FILE
        mv $IMAGE_IVT $image
    fi

    setEncryptedCSFFile $1
}


###############################################################################
# function: setEncryptedCSFFile()
#
# parameters: $1: IMAGE_NAME
#
# return: -
#
# description:
# This function set all the remaining wildcards in the "boot_in.csf"
# and runs the cst_encrypt tool to genarate a signed and encpted image.
#
###############################################################################
function setEncryptedCSFFile()
{
    local OFFSET_ENC=0x100
    local OFFSET=0x0
    local ADDR=0x"$LOAD_ADDRESS"
    local SIZE_DEC=$(stat -c %s "$image")
    local KEY_ADDR=0x`printf "%08x" $(($SIZE_DEC+$ADDR))`
    local IMAGE_SIZE=0x$BOOT_DATA_LENGTH
    local SIZE=0x100
    local ADDR_DEC=$(($ADDR + $SIZE))
    ADDR_DEC=0x`printf "%08x" "$ADDR_DEC"`
    TARGET="${IMAGE_NAME}_enc_${MASTER_KEY}"

    cp boot_in.csf boot_in.csf_temp

    # length minus 48 Bytes are signed
    SIZE_DEC=0x`printf "%08x" $(($SIZE_DEC-$SIZE))`

    if [[ "$1" == *"nboot"* ]]; then
        OFFSET=0x400
        OFFSET_ENC=0x500
        local TRUNCATE_SIZE=`grep -a -o -b "##CSF##" "$image" | \
        sed -e "s/:.*//"`
        KEY_ADDR=0x`printf "%08x" $(($TRUNCATE_SIZE+$ADDR-$OFFSET))`
	if [ "$KEY_LENGTH" == "128" ]; then
	    local CSF_ADDR_TEMP="$[KEY_ADDR + 0x48]"      # 72 Bytes
	elif [ "$KEY_LENGTH" == "192" ]; then
	    local CSF_ADDR_TEMP="$[KEY_ADDR + 0x50]"      # 80 Bytes
	elif [ "$KEY_LENGTH" == "256" ]; then
	    local CSF_ADDR_TEMP="$[KEY_ADDR + 0x58]"      # 88 Bytes
	fi

	SIZE_DEC="$[TRUNCATE_SIZE -0x500]"
	local CSF_ADDR=`printf "%08x" "$CSF_ADDR_TEMP"`

	local temp=`echo ${CSF_ADDR:6:2}${CSF_ADDR:4:2}${CSF_ADDR:2:2}\
${CSF_ADDR:0:2}`
	local out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
	temp=\\x$out
	out=${temp::-2}
	printf $out | dd conv=notrunc status=none of=$image bs=1 \
	seek=$((0x418))
	truncate -s $TRUNCATE_SIZE $image

	# set output name
	TARGET="${TARGET}.bin"
	IMAGE_SIZE=0x10000
    else
        if [[ "$1" == *"uboot"* ]]; then
             TARGET="${TARGET}.nb0"
        elif [ "$1" == "devtree" ]; then
	    TARGET="${image}_enc"
        fi
    fi

    # make SIZE_DEK a multiple of 16
    SIZE_DEC=`echo $(( SIZE_DEC / 16 ))`
    SIZE_DEC=`echo $(( SIZE_DEC * 16 ))`
    SIZE_DEC=0x`printf "%x" "$SIZE_DEC"`

    sed -e "s/###ADDR###/$ADDR/" -e "s/###OFFSET###/$OFFSET/" \
        -e "s/###SIZE###/$SIZE/" -e "s/###BOOT###/$image/" \
        -e "s/###length###/$KEY_LENGTH/" -e "s/###KEY_ADDR###/$KEY_ADDR/" \
        -e "s/###ADDR_DEC###/$ADDR_DEC/" -e "s/###OFFSET_ENC###/$OFFSET_ENC/" \
        -e "s/###SIZE_DEC###/$SIZE_DEC/"  boot_in.csf > boot_in.csf_temp

    if [ "$MASTER_KEY" == "zmk" ]; then
        sed -e "s/###MASTER_KEY###/2/" boot_in.csf_temp > temp.csf
        sed -e '44,$s/#//' temp.csf > boot_in.csf_temp
        cp -r boot_in.csf_temp temp.csf
    else
        sed -e "s/###MASTER_KEY###/0/" boot_in.csf_temp > temp.csf
        sed -e '44,$s/#//' temp.csf > boot_in.csf_temp
        cp -r boot_in.csf_temp temp.csf
    fi
    rm boot_in.csf_temp
    # check if NBoot use ZMK then set ZMK key
    if [[ "$1" == *"nboot"* ]] && [ "$MASTER_KEY" == "zmk" ]; then
	sed -e '18,20s/#//' -e '21,36s/#//' temp.csf > boot_in.csf
    else
        cp -r temp.csf boot_in.csf
    fi

    # generate no output on stdout
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
    rm temp.csf
    rm $TARGET-temp
    rm csf.bin
    rm dek_blob.bin
    rm dek.bin
    rm $image
    rm boot_in.csf

    objcopy -I binary -O binary --pad-to=$IMAGE_SIZE --gap-fill=0xFF $TARGET \
    $TARGET
}


###############################################################################
# function: getDekBlob()
#
# parameters: $1: key length (128/192/256)
#
# return: -
#
# description:
# Generates the dek_blob.bin from given key (created on the board).
#
###############################################################################
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

    if [ "$KEY_LENGTH" == "128" ]; then
	let CSF_ADDR="$CSF_ADDR + 0x48"
    elif [ "$KEY_LENGTH" == "192" ]; then
	let CSF_ADDR="$CSF_ADDR + 0x50"
    elif [ "$KEY_LENGTH" == "256" ]; then
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

    runFakeCST "$2"

    local temp_length=`echo ${BOOT_DATA_LENGTH:6:2}${BOOT_DATA_LENGTH:4:2}\
${BOOT_DATA_LENGTH:2:2}${BOOT_DATA_LENGTH:0:2}`
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
# parameters: $1: image type
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
	case $1 in
	    *nboot*)
                BOOT_DATA_LENGTH=10000
	        BOOT_DATA_LENGTH=`printf "%08d" $BOOT_DATA_LENGTH`
                ;;
            *uboot_vyb*)
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
	        -e "s/###length###/$KEY_LENGTH/" \
	        -e "s/###KEY_ADDR###/0x$LOAD_ADDRESS/" \
	        -e "s/###ADDR_DEC###/0x$LOAD_ADDRESS/" \
	        -e "s/###OFFSET_ENC###/0x100/" -e "s/###SIZE_DEC###/0x10/" \
	        -e  "s/###MASTER_KEY###/0/" boot_in.csf > boot_in.csf_temp
	    sed -e '44,$s/#//' boot_in.csf_temp > boot_fake.csf
	    cp $image ${image}-bak

	    # suppress output generated by the cst tool
	    cst-2.3.2/linux64/cst_encrypt --o csf.bin --i boot_fake.csf \
	    1>/dev/null

	    if [ "$?" != "0" ]; then
		success=false
	    fi

	    cat $image csf.bin > ${image}_fake
	    BOOT_DATA_LENGTH=$(stat -c %s "${image}_fake")
	    let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 1"

	    BOOT_DATA_LENGTH=$((($BOOT_DATA_LENGTH+15)/16))
	    BOOT_DATA_LENGTH=$(($BOOT_DATA_LENGTH * 16))
	    # add the 0x40 (64) Byte header (0x20 IVT, 0x20 BOOT_DATA)
	    let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 64"

            # add key length to size
	    if [ "$KEY_LENGTH" == "128" ]; then
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x48"
	    elif [ "$KEY_LENGTH" == "192" ]; then
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x50"
	    elif [ "$KEY_LENGTH" == "256" ]; then
		let BOOT_DATA_LENGTH="$BOOT_DATA_LENGTH + 0x58"
	    fi

	    BOOT_DATA_LENGTH=`printf "%08x" $BOOT_DATA_LENGTH`
	    rm ${image}_fake
	    rm boot_fake.csf
	    mv ${image}-bak $image
	esac
}


# main function

handleParameters "$@"
checkEncryptionTool
if [ $CHECK_NBOOT_FOR_KEYS == true ]; then
    checkNBootForEncryption
    exit 0
fi
setCertNumberEncrypting
getImageToBeEncrypted
getImageType $image

if [[ "$IMAGE_NAME" != *"nboot"* ]]; then
	createBootDataHeader $image $IMAGE_NAME enc
	createIVTHeader $image $IMAGE_NAME
fi

makeEncryptedImage $IMAGE_NAME
if [ "$?" == "0" ]; then
	printf "${LIGHT_GREEN}Encrypted image (%s) successfully generated.
	${NORMAL}\b\n" "$TARGET"
else
	printf "${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
fi

if [ "$success" == "false" ]; then
    printf "Error, image couldn't be generated!\b\n"
    exit 1
fi

exit 0

