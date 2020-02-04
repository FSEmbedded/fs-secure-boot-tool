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
# return:     -
#
# description:
# This functions stores the script parameters in global(!) variables. Big
# letter variables are files/directories, small letter variables are just
# variables.
#
###############################################################################
function handleParameters()
{
	cpu_arch=$1
	OUTPUT_NAME=$2
	custom_load_address=$3
	IMAGE_PATH=$4
	key_length=$5
	master_key=$6
	engine=$7
	CST_DIR=$8
	CST_BINARY=$9
}


###############################################################################
# function: setup_variables
#
# parameters: -
#
# return:     -
#
# description:
# Setup some global variables. Big letter variables are files/directories,
# small letter variables are just variables.
#
###############################################################################
function setup_variables()
{
	# big letter names are files/directories
	# create folder '_tmp' which contains all created temporary files and the
	# corresponding global variable
	TMP_DIR=_tmp
	mkdir -p $TMP_DIR
	IMAGE=0
	TMP_IMAGE=temp_image.bin
	BOOT_IN_CSF=boot_in.csf
	BOOT_IN_CSF_FAKE=boot_in.csf_fake
	BOOT_IN_CSF_FAKE_2=boot_in.csf_fake_2
	BOOT_RAW_EDITED=boot_raw_edited
	CSF_BIN=csf.bin
	TARGET_NAME=0
	DEK_BLOB=dek_blob.bin
	# small letter are just variables
	load_address=0
	image_name=0
	signing_size=0
	signed_image_length=0
}


###############################################################################
# function: checkEncryptionTool()
#
# parameters: -
#
# return:     -
#
# description:
# Checks if the cst tool is enabled for encryption or not.
#
###############################################################################
function checkEncryptionTool()
{
	if [ ! -f "$CST_BINARY" ]; then
		local cur_dir=$PWD
		cd $CST_DIR/code/back_end/src
		gcc -o cst_encrypt -I ../hdr -L ../../../linux64/lib *.c -lfrontend \
		-lcrypto
		if [ "$?" == "0" ]; then
			cp cst_encrypt $CST_BINARY
		else
			printf "\n$CST_BINARY could not be created! Aborting....\n\n"
			exit 1
		fi
		cd $cur_dir
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
# This function sets the numbers in the boot.csf-in file depending which
# created certificate should be used (is treated as '1'). Not implemented yet!
#
###############################################################################
function setCertNumberEncrypting()
{
#    path=./release/crts/
#    local quantity=`ls -d ${path}SRK*.pem | wc -l`
#    printf "Which certificate do you want to use for signing"
#    printf " (1-%u)?\b\n" "$quantity"
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

	sed -e "s/###INDEX###/$temp/" -e "s/###NUM###/$num/" $BOOT_RAW_EDITED > \
	$TMP_DIR/$BOOT_IN_CSF

	if [ "$?" != "0" ]; then
		printf "\nFunction setCertNumberEncrypting() failed! Aborting ....\n\n"
		rm -r $TMP_DIR
		exit 1
	fi
}


###############################################################################
# function: getImageToBeEncrypted()
#
# parameters: -
#
# return: -
#
# description:
# Copies the specified image to the $TMP_DIR directory and stores it's name in
# a global variable.
#
###############################################################################
function getImageToBeEncrypted()
{
	local DIR=`dirname "$IMAGE_PATH"`

	IMAGE=`basename "$IMAGE_PATH"`

	# copy file to current directory if not already exists
	if ! [ "$PWD" == "$DIR" ]; then
		cp "$IMAGE_PATH" $TMP_DIR/
	else
		printf "$IMAGE already exists in $PWD. Using existing one.\n"
		mv $IMAGE $TMP_DIR/
	fi

	# since we take the u-boot.bin image, let's rename it to uboot.nb0
	if [ "$TMP_DIR/$IMAGE" == "u-boot.bin" ]; then
		mv $TMP_DIR/$IMAGE $TMP_DIR/uboot.nb0
		$TMP_DIR/IMAGE=uboot.nb0
	fi
}


###############################################################################
# function: getImageType()
#
# parameters: -
#
# return:     -
#
#             load_address, image_name (global variable!!)
#
# description:
# Check ImageType and set image_name and load address.
#
###############################################################################
function getImageType()
{
	# check magic numbers in given image
	local MAGIC_NUMBER_N=`hexdump -n 4 -s 0x400 -e '"%x\n"' "$TMP_DIR/$IMAGE"`
	local MAGIC_NUMBER_E=`hexdump -n 4 -s 0x40 -e '"%x\n"' "$TMP_DIR/$IMAGE"`
	local MAGIC_NUMBER_U=`hexdump -n 4 -s 0x3c -e '"%x\n"' "$TMP_DIR/$IMAGE"`
	local MAGIC_NUMBER_M4=`hexdump -n 4 -s 0x0 -e '"%x\n"' "$TMP_DIR/$IMAGE"`
	local MAGIC_NUMBER_UIMAGE=`hexdump -n 4 -s 0x0 -e \
	'"%x\n"' "$TMP_DIR/$IMAGE"`
	local MAGIC_NUMBER_ZIMAGE=`hexdump -n 4 -s 0x24 -e \
	'"%x\n"' "$TMP_DIR/$IMAGE"`
	local MAGIC_NUMBER_DEVTREE_FIT_IMAGE=`hexdump -n 4 -s 0x0 -e \
	'"%x\n"' "$TMP_DIR/$IMAGE"`

	if [ "$MAGIC_NUMBER_N" == "402000d1" ]; then
		load_address=907000
		image_name="nboot_${cpu_arch}"
		TARGET_NAME="${image_name}_enc_${master_key}.bin"
		# normally this will set by runFakeCST but NBoot doesn´t call this
		# function so set the length manually because it´s always the same.
		signed_image_length=10000
		signed_image_length=`printf "%08d" $signed_image_length`
		# length is 0x42c, but offset is 0x10 so new length is 0x41c
		# sign NBoot till boot_data_header and the code afterwards is encrypted
		signing_size=0x41c
		printf "NBoot detected!\n"
	elif [ "$MAGIC_NUMBER_U" == "12345678" ]; then
		local UBOOT_NUMBER=`hexdump -n 4 -s 0x20 -e '"%x\n"' "$TMP_DIR/$IMAGE"`
		local uboot_addr=$(( 0x$UBOOT_NUMBER & 0xFFFF0000 ))
		local uboot_addr_hex=`printf "%x" "$uboot_addr"`
		# set global variables
		load_address="$uboot_addr_hex"
		image_name="uboot_${cpu_arch}"
		TARGET_NAME="${image_name}_enc_${master_key}.nb0"
		# sign image till uboot magic number and encrypt everything afterwards
		signing_size=0x80
		printf "U-Boot detected!\n"
	elif [ "$MAGIC_NUMBER_UIMAGE" == "56190527" ]; then
		local kernel_load_addr=`hexdump -n 4 -s 0x14 -e '"%08x\n"' \
		"$TMP_DIR/$IMAGE"`
		# change endianess and set global variables
		load_address=`echo ${kernel_load_addr:6:2}${kernel_load_addr:4:2}\
${kernel_load_addr:2:2}${kernel_load_addr:0:2}`
		image_name="uImage_${cpu_arch}"
		TARGET_NAME="${image_name}_enc_${master_key}"
		# sign complete uImage header and encrypt code afterwards
		signing_size=0x80
		printf "Legacy Image detected!\n"
	elif [ "$MAGIC_NUMBER_ZIMAGE" == "16f2818" ]; then
		# set global variables
		if [ "$cpu_arch" == "sdq" ]; then
			load_address=11000000
		else
			load_address=81000000
		fi
		image_name="zImage_${cpu_arch}"
		TARGET_NAME="${image_name}_enc_${master_key}"
		# sign image till zImage magic number and encrypt everything afterwards
		signing_size=0x68
		printf "zImage detected!\n"
	elif [ "$MAGIC_NUMBER_DEVTREE_FIT_IMAGE" == "edfe0dd0" ]; then
		# set global variables
		if [ "$cpu_arch" == "sdq" ]; then
			load_address=12000000
		else
			load_address=82000000
		fi
		if [ "`grep -cE "description|timestamp" $TMP_DIR/$IMAGE`" -gt "1" ]; \
		then
			local fit_image_offset=1000000
			let load_address="$load_address + $fit_image_offset"
			printf "FIT image detected!\n"
		else
			printf "Device Tree detected!\n"
		fi
		image_name="devtree_fit-image"
		TARGET_NAME="${IMAGE}_enc_${master_key}"
		# sign complete FIT/DT-Image header and encrypt code afterwards
		signing_size=0x68
	elif [ "$MAGIC_NUMBER_E" == "43454345" ] || \
			[ "$MAGIC_NUMBER_M4" == "4d344d34" ]; then
		printf "E-Boot/M4 image not yet supported! Aborting....\n"
		rm -r $TMP_DIR
		exit 1
	else
		printf "Image type not supported! Aborting....\n"
		rm -r $TMP_DIR
		exit 1
	fi

	if [ -n "$custom_load_address" ]; then
		load_address=$custom_load_address
	fi
}


###############################################################################
# function: createEncryptedImage()
#
# parameters: $1: IMAGE_NAME
#
# return: -
#
# description:
# This function sets all the remaining wildcards in the "boot_in.csf"
# and runs the cst tool to generate an encrypted image. Warning, TARGET is a
# globalvariable!!
#
###############################################################################
function createEncryptedImage()
{
	local load_address_hex=0x"$load_address"
	local image_size=$(stat -c %s "$TMP_DIR/$IMAGE")
	local signing_address="$load_address_hex"
	local signing_offset=0x0
	local encrypting_address=0
	local encrypting_offset=0
	local encrypting_length=0
	local key_addr=0x`printf "%08x" $(($load_address_hex+$image_size))`

	# image size in hex
	image_size=0x`printf "%08x" "$image_size"`

	if [[ "$image_name" == *"nboot"* ]]; then
		local csf_offset=0
		# signing begins at offset 0x14
		signing_offset=0x14
		# get offset where signature must be located. This is also the length
		# of the image without signature.
		image_size=`grep -a -o -b "##CSF##" "$TMP_DIR/$IMAGE" | \
				sed -e "s/:.*//"`
		# cut NBoot image at ###CSF###
		truncate -s $image_size $TMP_DIR/$IMAGE
		if [ "$?" != "0" ]; then
			printf "\nFunction createEncryptedImage() failed! Aborting....\n\n"
			rm -r $TMP_DIR
			return 1
		fi
		# convert image_size to hex value
		image_size=0x`printf "%x" "$image_size"`

		# start address of dek_blob key
		key_addr=0x`printf "%08x" $(($load_address_hex + $image_size))`

		# calc csf_offset
		if [ "$key_length" == "128" ]; then
			csf_offset="$[key_addr + 0x48]"      # 72 Bytes
		elif [ "$key_length" == "192" ]; then
			csf_offset="$[key_addr + 0x50]"      # 80 Bytes
		elif [ "$key_length" == "256" ]; then
			csf_offset="$[key_addr + 0x58]"      # 88 Bytes
		fi

		# convert to hex value
		csf_offset=`printf "%08x" $(($csf_offset))`

		# change endian
		local csf_offset_bin=`echo ${csf_offset:6:2}${csf_offset:4:2}\
${csf_offset:2:2}${csf_offset:0:2}`
		# insert \x every Byte so it can interpreted as a binary file
		local out=`echo -n -e $csf_offset_bin | sed -e 's/.\{2\}/&\\\x/g'`
		# insert \x at the beginning
		csf_offset_bin=\\x$out
		# remove \x at the end
		out=${csf_offset_bin::-2}
		# replace 32 bit value at image offset 0x418. Replace image csf address
		# with new calculated csf address.
		printf $out | dd conv=notrunc status=none of=$TMP_DIR/$IMAGE bs=1 \
		seek=$((0x418))
	fi

	# setup signing_address
	let signing_address="$load_address_hex + $signing_offset"
	signing_address=0x`printf "%x" "$signing_address"`

	# setup new encrypting address
	encrypting_address=0x`printf "%08x" $(($load_address_hex + $signing_offset \
	+ $signing_size))`
	# length minus signing size
	encrypting_length=0x`printf "%x" $(($image_size - $signing_offset - \
	$signing_size))`
	# calculate encrypting offset (start address)
	encrypting_offset=0x`printf "%x" $(($signing_offset+$signing_size))`

	# make encrypting_length a multiple of 16
	encrypting_length=`echo $(( encrypting_length / 16 ))`
	encrypting_length=`echo $(( encrypting_length * 16 ))`
	encrypting_length=0x`printf "%x" "$encrypting_length"`

	sed -e "s/###ADDR###/$signing_address/" \
	-e "s/###OFFSET###/$signing_offset/" -e "s/###SIZE###/$signing_size/" \
	-e "s|###BOOT###|$TMP_DIR/$IMAGE|" -e "s/###length###/$key_length/" \
	-e "s/###KEY_ADDR###/$key_addr/" \
	-e "s/###ADDR_DEC###/$encrypting_address/" \
	-e "s/###OFFSET_ENC###/$encrypting_offset/" \
	-e "s/###SIZE_DEC###/$encrypting_length/" -e "s/###ENGINE###/$engine/" \
	"$TMP_DIR/$BOOT_IN_CSF" > "$TMP_DIR/$BOOT_IN_CSF_FAKE"

	if [ "$master_key" == "otpmk" ]; then
		sed -e "s/###MASTER_KEY###/0/" $TMP_DIR/$BOOT_IN_CSF_FAKE > \
		$TMP_DIR/$BOOT_IN_CSF_FAKE_2
		sed -e '21,$s/#//' $TMP_DIR/$BOOT_IN_CSF_FAKE_2 > \
		$TMP_DIR/$BOOT_IN_CSF_FAKE
    fi
	mv $TMP_DIR/$BOOT_IN_CSF_FAKE $TMP_DIR/$BOOT_IN_CSF
	# generate no output on stdout
	$CST_BINARY --o $TMP_DIR/$CSF_BIN --i $TMP_DIR/$BOOT_IN_CSF
	if [ "$?" != "0" ]; then
		printf "\nCan not create signature! Aborting....\n\n"
		rm -r $TMP_DIR
		return 1
	fi

	# copy key to tftpboot folder if exists
	if [ -d /tftpboot ]; then
		cp dek.bin /tftpboot
		rm dek.bin
	else
		printf "Directory /tftpboot not found, dek.bin is available in $PWD\n"
		if [ -d bin ]; then
			mv dek.bin bin/
		fi
	fi

	# parse dek_blob and copy to $TMP_DIR/$DEK_BLOB
	getDekBlob $key_length

	if [ -n "$OUTPUT_NAME" ]; then
		TARGET_NAME="$OUTPUT_NAME"
	fi

	# merge image + signature together
	cat $TMP_DIR/$IMAGE $TMP_DIR/$DEK_BLOB > $TMP_DIR/$TMP_IMAGE
	cat $TMP_DIR/$TMP_IMAGE $TMP_DIR/$CSF_BIN > $TMP_DIR/$TARGET_NAME

	# check if NBoot image bigger than 0xd800
	image_size=$(stat -c %s "$TMP_DIR/$TARGET_NAME")
	if [[ $image_size -gt 0xd800 ]] && [[ "$image_name" == *"nboot"* ]]; then
		printf "${LIGHT_RED}Error max image size = 0xd800, current image "
		printf "size = 0x%x!${NORMAL}\b\n" "$image_size"
		rm -r $TMP_DIR
		return 1
	elif [[ $image_size -gt 0x80000 ]] && \
		 [[ "$image_name" == *"uboot"* ]]; then
		printf "${LIGHT_RED}Error max image size = 0x80000, current image "
		printf "size = 0x%x!${NORMAL}\b\n" "$image_size"
		rm -r $TMP_DIR
		return 1
	else
		objcopy -I binary -O binary --pad-to=0x$signed_image_length \
		--gap-fill=0xFF $TMP_DIR/$TARGET_NAME $TMP_DIR/$TARGET_NAME
	fi

	# create bin folder if not exists and copy image
	mkdir -p bin
	\cp $TMP_DIR/$TARGET_NAME bin
	# delete temp files
	rm -r $TMP_DIR

	return 0
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
	printf $str > $TMP_DIR/$DEK_BLOB
}


###############################################################################
# function: createIVTHeader()
#
# parameters: -
#
# return:     -
#
# description:
# This function creates the IVT header and adds it at the beginning of the
# image.
#
###############################################################################
function createIVTHeader()
{
	local ivt_header=402000D1
	local IVT_TARGET=`echo "${image_name}_ivt.bin"`
	local image_size=$(stat -c %s "$TMP_DIR/$IMAGE")
	local csf_absolute_addr=0
	local ZEROS=00000000
	local boot_data_absolute_addr=0
	local entry_point_addr=0

	let boot_data_absolute_addr="$load_address + 20"
	let entry_point_addr="$load_address + 40"

	### -> HEADER <- ###
	# change big endians to little endians
	local temp=`echo ${ivt_header:6:2}${ivt_header:4:2}${ivt_header:2:2}\
${ivt_header:0:2}`
	# insert \x every Byte so it can interpreted as a binary file
	local out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
	# insert \x at the beginning
	temp=\\x$out
	# remove \x at the end
	final=${temp::-2}
	echo -n -e $final > $TMP_DIR/$IVT_TARGET

	### -> ENTRY <- ###
	# change big endians to little endians
	temp=`echo ${entry_point_addr:6:2}${entry_point_addr:4:2}\
${entry_point_addr:2:2}${entry_point_addr:0:2}`
	# insert \x every Byte so it can interpreted as a binary file
	out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
	# insert \x at the beginning
	temp=\\x$out
	# remove \x at the end
	final=${temp::-2}
	echo -n -e $final >> $TMP_DIR/$IVT_TARGET

	### -> RESERVED1 and DCD <- ###
	# insert \x every Byte so it can interpreted as a binary file
	out=`echo -n -e $ZEROS | sed -e 's/.\{2\}/&\\\x/g'`
	# insert \x at the beginning
	temp=\\x$out
	local zeroes=${temp::-2}
	echo -n -e $zeroes >> $TMP_DIR/$IVT_TARGET
	echo -n -e $zeroes >> $TMP_DIR/$IVT_TARGET

	### -> BOOT_DATA <- ###
	# change big endians to little endians
	temp=`echo ${boot_data_absolute_addr:6:2}${boot_data_absolute_addr:4:2}\
${boot_data_absolute_addr:2:2}${boot_data_absolute_addr:0:2}`
	# insert \x every Byte so it can interpreted as a binary file
	out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
	# insert \x at the beginning
	temp=\\x$out
	# remove \x at the end
	final=${temp::-2}
	echo -n -e $final >> $TMP_DIR/$IVT_TARGET

	### -> SELF <- ###
	# selfpointer = load_address, because ivt have no offset
	# change big endians to little endians
	temp=`echo ${load_address:6:2}${load_address:4:2}${load_address:2:2}\
${load_address:0:2}`
	# insert \x every Byte so it can interpreted as a binary file
	out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
	# insert \x at the beginning
	temp=\\x$out
	# remove \x at the end
	final=${temp::-2}
	echo -n -e $final >> $TMP_DIR/$IVT_TARGET

	### -> CSF <- ###
	# increment image_size depending on the key_length
	if [ "$key_length" == "128" ]; then
		let image_size="$image_size + 0x48"
	elif [ "$key_length" == "192" ]; then
		let image_size="$image_size + 0x50"
	elif [ "$key_length" == "256" ]; then
		let image_size="$image_size + 0x58"
	fi
	# in createBootDataHeader the image itself is merged with boot_data_header
	# so if we stat the image here the $image_size => sizeof image +
	# boot_data-header so we have subtract the boot_data_header to get the real
	# image size. Boot_data_header has a fix size 0x20 => 32 (decimal).
	image_size=`printf "%d "$(($image_size-32))`
	image_size=`printf "%08x" $image_size`
	csf_absolute_addr=`printf "%08x" $((0x$image_size+0x$entry_point_addr))`
	# change big endians to little endians
	temp=`echo ${csf_absolute_addr:6:2}${csf_absolute_addr:4:2}\
${csf_absolute_addr:2:2}${csf_absolute_addr:0:2}`
	# insert \x every Byte so it can interpreted as a binary file
	out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
	# insert \x at the beginning
	temp=\\x$out
	# remove \x at the end
	final=${temp::-2}
	echo -n -e $final >> $TMP_DIR/$IVT_TARGET

	### -> RESERVED2 <- ###
	# insert \x every Byte so it can interpreted as a binary file
	out=`echo -n -e $ZEROS | sed -e 's/.\{2\}/&\\\x/g'`
	# insert \x at the beginning
	temp=\\x$out
	# remove \x at the end
	final=${temp::-2}
	echo -n -e $final >> $TMP_DIR/$IVT_TARGET

	# merge IVT and image together
	cat $TMP_DIR/$IVT_TARGET $TMP_DIR/$IMAGE > $TMP_DIR/$TMP_IMAGE
	mv $TMP_DIR/$TMP_IMAGE $TMP_DIR/$IMAGE
}


###############################################################################
# function: createBootDataHeader()
#
# parameters: -
#
# return:     -
#
# description:
# This function creates the BOOT DATA header and adds it at the beginning of
# the image.
#
###############################################################################
function createBootDataHeader()
{
	local zero_pad=00000000
	local zero_pad_bin=0
	local ff_pad=FFFFFFFF
	local ff_pad_bin=0
	local load_addr_bin=0
	local img_length_total_le=0
	local img_length_total_le_bin=0
	local temp_value=0
	local BOOT_DATA_HEADER=`echo "${image_name}_boot_data.bin"`
	local image_size=$(stat -c %s "$TMP_DIR/$IMAGE")

	if [[ "$image_name" == *"uImage"* ]]; then
		# insert \x every Byte so it can interpreted as a binary file
		local load_addr_bin=`echo -n -e $load_address | \
		sed -e 's/.\{2\}/&\\\x/g'`
	else
		# change big endians to little endians
		load_addr_bin=`echo ${load_address:6:2}${load_address:4:2}\
${load_address:2:2}${load_address:0:2}`
		# insert \x every Byte so it can interpreted as a binary file
		load_addr_bin=`echo -n -e $load_addr_bin | sed -e 's/.\{2\}/&\\\x/g'`
	fi

	# round image_size up to the next 0x10 boundary (left-adjusted)
	image_size=$((($image_size+15)/16))
	image_size=$(($image_size * 16))
	# pad image to the next 0x10 boundary (left-adjusted)
	objcopy -I binary -O binary --pad-to=$image_size --gap-fill=0xFF \
	$TMP_DIR/$IMAGE $TMP_DIR/$IMAGE

	# call runFakeCST
	runFakeCST

	# change big endians to little endians
	img_length_total_le=`echo ${signed_image_length:6:2}\
${signed_image_length:4:2}${signed_image_length:2:2}${signed_image_length:0:2}`

	# insert \x every Byte so it can interpreted as a binary file
	zero_pad_bin=`echo -n -e $zero_pad | sed -e 's/.\{2\}/&\\\x/g'`
	ff_pad_bin=`echo -n -e $ff_pad | sed -e 's/.\{2\}/&\\\x/g'`
	img_length_total_le_bin=`echo -n -e $img_length_total_le | \
	sed -e 's/.\{2\}/&\\\x/g'`

	# create boot data header as a binary
	# insert \x at the beginning
	temp_value=\\x$load_addr_bin
	# remove \x at the end
	temp_value=${temp_value::-2}
	echo -n -e $temp_value > $TMP_DIR/$BOOT_DATA_HEADER

	# insert \x at the beginning
	temp_value=\\x$img_length_total_le_bin
	# remove \x at the end
	temp_value=${temp_value::-2}
	echo -n -e $temp_value >> $TMP_DIR/$BOOT_DATA_HEADER

	# insert \x at the beginning
	temp_value=\\x$zero_pad_bin
	# remove \x at the end
	temp_value=${temp_value::-2}
	echo -n -e $temp_value >> $TMP_DIR/$BOOT_DATA_HEADER

	# insert \x at the beginning
	temp_value=\\x$ff_pad_bin
	# remove \x at the end
	temp_value=${temp_value::-2}
	echo -n -e $temp_value >> $TMP_DIR/$BOOT_DATA_HEADER

	# insert \x at the beginning
	temp_value=\\x$ff_pad_bin
	# remove \x at the end
	temp_value=${temp_value::-2}
	echo -n -e $temp_value >> $TMP_DIR/$BOOT_DATA_HEADER

	# insert \x at the beginning
	temp_value=\\x$ff_pad_bin
	# remove \x at the end
	temp_value=${temp_value::-2}
	echo -n -e $temp_value >> $TMP_DIR/$BOOT_DATA_HEADER

	# insert \x at the beginning
	temp_value=\\x$ff_pad_bin
	# remove \x at the end
	temp_value=${temp_value::-2}
	echo -n -e $temp_value >> $TMP_DIR/$BOOT_DATA_HEADER

	# insert \x at the beginning
	temp_value=\\x$ff_pad_bin
	# remove \x at the end
	temp_value=${temp_value::-2}
	echo -n -e $temp_value >> $TMP_DIR/$BOOT_DATA_HEADER

	# merge boot_data_header and image together
	cat $TMP_DIR/$BOOT_DATA_HEADER $TMP_DIR/$IMAGE > $TMP_DIR/$TMP_IMAGE
	mv $TMP_DIR/$TMP_IMAGE $TMP_DIR/$IMAGE
}


###############################################################################
# function: runFakeCST()
#
# parameters: -
#
# return:     -
#
#             signed_image_length (global variable!!)
#
#
# description:
# Runs the cst tool using fake options in order to create a temporary binary
# csf file. We need this binary file to calculate the exact image length (image
# + signature) for the boot data header. The length is stored in
# $signed_image_length (global variable!!).
#
###############################################################################
runFakeCST()
{
	case $image_name in
		*nboot*)
			# normally not called because ivt already exists
			signed_image_length=10000
			signed_image_length=`printf "%08d" $signed_image_length`
			;;
		*uboot_vyb*)
			signed_image_length=60000
			signed_image_length=`printf "%08d" $signed_image_length`
			;;
		*uboot*)
			signed_image_length=80000
			signed_image_length=`printf "%08d" $signed_image_length`
			;;
		*)
			sed -e "s/###ADDR###/0x$load_address/" -e "s/###OFFSET###/0x0/" \
				-e "s/###SIZE###/0x10/" -e "s|###BOOT###|$TMP_DIR/$IMAGE|" \
				-e "s/###length###/$key_length/" \
				-e "s/###KEY_ADDR###/0x$load_address/" \
				-e "s/###ADDR_DEC###/0x$load_address/" \
				-e "s/###OFFSET_ENC###/0x100/" -e "s/###SIZE_DEC###/0x10/" \
				-e  "s/###MASTER_KEY###/0/" -e "s/###ENGINE###/$engine/" \
				"$TMP_DIR/$BOOT_IN_CSF" > "$TMP_DIR/$BOOT_IN_CSF_FAKE"
			sed -e '21,$s/#//' "$TMP_DIR/$BOOT_IN_CSF_FAKE" > \
			$TMP_DIR/$BOOT_IN_CSF_FAKE_2
			# make save copy
			cp $TMP_DIR/$IMAGE $TMP_DIR/${IMAGE}-bak

			# suppress output generated by the cst tool
			$CST_BINARY --o $TMP_DIR/$CSF_BIN --i \
			$TMP_DIR/$BOOT_IN_CSF_FAKE_2 1>/dev/null
			if [ "$?" != "0" ]; then
				printf "\nFunction runFakeCST() failed! Aborting ....\n\n"
				rm -r $TMP_DIR
				exit 1
			fi

			# setup signed_image_size
			local image_size=$(stat -c %s "$TMP_DIR/${IMAGE}")
			local signature_size=$(stat -c %s $TMP_DIR/$CSF_BIN)
			let signed_image_length="$image_size + $signature_size + 1"
			signed_image_length=$((($signed_image_length+15)/16))
			signed_image_length=$(($signed_image_length * 16))
			# add the 0x40 (64) Byte header (0x20 IVT, 0x20 BOOT_DATA)
			let signed_image_length="$signed_image_length + 64"

			# add key length to size
			if [ "$key_length" == "128" ]; then
				let signed_image_length="$signed_image_length + 0x48"
			elif [ "$key_length" == "192" ]; then
				let signed_image_length="$signed_image_length + 0x50"
			elif [ "$key_length" == "256" ]; then
				let signed_image_length="$signed_image_length + 0x58"
			fi

			signed_image_length=`printf "%08x" $signed_image_length`
			# copy original image back
			mv $TMP_DIR/${IMAGE}-bak $TMP_DIR/$IMAGE
	    ;;
	esac
}


# main function
handleParameters "$@"
setup_variables
checkEncryptionTool
setCertNumberEncrypting
getImageToBeEncrypted
getImageType

if [[ "$image_name" != *"nboot"* ]]; then
	createBootDataHeader
	createIVTHeader
fi

createEncryptedImage
if [ "$?" == "0" ]; then
	printf "${LIGHT_GREEN}Encrypted image (%s) successfully generated.
			${NORMAL}\b\n" "$TARGET_NAME"
	exit 0
else
	printf "\n${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
	exit 1
fi

