#!/bin/bash

# define constants

NORMAL='\033[0m'
LIGHT_GREEN='\033[1;32m'
LIGHT_RED='\033[0;31m'

FSH_FLAGS_DESCR=0x8000
FSH_FLAGS_CRC32=0x4000
FSH_FLAGS_SECURE=0x2000


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
	engine=$5
	CST_BINARY=$6
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
	if [ -d $TMP_DIR ]; then
		rm -r $TMP_DIR
	fi
	mkdir -p $TMP_DIR
	IMAGE=0
	TMP_IMAGE=temp_image.bin
	BOOT_IN_CSF=boot_in.csf
	BOOT_IN_CSF_FAKE=boot_in.csf_fake
	BOOT_RAW_EDITED=boot_raw_edited
	CSF_BIN=csf.bin
	TARGET_NAME=0
	# small letter are just variables
	load_address=0
	image_name=0
	signed_image_length=0
	#sizes
	field_size=4
	header_size=64
	#fs script offsets
	fs_magic_fslx=0
	fs_image_size_low=4
	fs_imge_size_high=8
	fs_type=16
	fs_arch=32
	#IVT offsets
	ivt_header=0
	ivt_entry=4
	ivt_boot_data=16
	ivt_self=20
	ivt_csf=24
	boot_data_start=32
	boot_data_length=36
	boot_data_plugin_flag=40
}


###############################################################################
# function: setCertNumberSigning()
#
# parameters: -
#
# return:     -
#
# description:
# This function sets the numbers in the boot.csf-in file depending which
# created certificate should be used (is treated as '1'). Not implemented yet!
#
###############################################################################
function setCertNumberSigning()
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
		printf "\nFunction setCertNumberSigning() failed! Aborting ....\n\n"
		rm -r $TMP_DIR
		exit 1
	fi
}


###############################################################################
# function: getImageToBeSigned()
#
# parameters: -
#
# return:     -
#
# description:
# Copies the specified image to the $TMP_DIR directory and stores it's name in
# a global variable.
#
###############################################################################
function getImageToBeSigned()
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
	local MAGIC_NUMBER_FS=`hexdump -n 4 -e '"%x"' "$TMP_DIR/$IMAGE"`
	local MAGIC_NUMBER_FS_IMAGE_TYPE=`hexdump -n 4 -s 16 -e \
	'"%x"' "$TMP_DIR/$IMAGE"`
	local MAGIC_NUMBER_AARCH64_ZIMAGE=`hexdump -n 4 -s 56 -e \
	'"%x"' "$TMP_DIR/$IMAGE"`

	if [ "$MAGIC_NUMBER_N" == "402000d1" ]; then
		load_address=907000
		image_name="nboot_${cpu_arch}"
		TARGET_NAME="${image_name}_signed.bin"
		# normally this will set by runFakeCST but NBoot doesn´t call this
		# function so set the length manually because it´s always the same.
		signed_image_length=10000
		signed_image_length=`printf "%08d" $signed_image_length`
		printf "NBoot detected!\n"
	elif [ "$MAGIC_NUMBER_U" == "12345678" ]; then
		local UBOOT_NUMBER=`hexdump -n 4 -s 0x20 -e '"%x\n"' "$TMP_DIR/$IMAGE"`
		local uboot_addr=$(( 0x$UBOOT_NUMBER & 0xFFFF0000 ))
		local uboot_addr_hex=`printf "%x" "$uboot_addr"`
		# set global variables
		load_address="$uboot_addr_hex"
		image_name="uboot_${cpu_arch}"
		TARGET_NAME="${image_name}_signed.nb0"
		printf "U-Boot detected!\n"
	elif [ "$MAGIC_NUMBER_UIMAGE" == "56190527" ]; then
		local kernel_load_addr=`hexdump -n 4 -s 0x14 -e '"%08x\n"' \
		"$TMP_DIR/$IMAGE"`
		# change endianess and set global variables
		load_address=`echo ${kernel_load_addr:6:2}${kernel_load_addr:4:2}\
${kernel_load_addr:2:2}${kernel_load_addr:0:2}`
		if [ "$cpu_arch" == "8mm" ]; then
			load_address=43800000
		fi
		image_name="uImage_${cpu_arch}"
		TARGET_NAME="${IMAGE}_signed"
		printf "Legacy Image detected!\n"
	elif [ "$MAGIC_NUMBER_ZIMAGE" == "16f2818" ]; then
		# set global variables
		if [ "$cpu_arch" == "sdq" ]; then
			load_address=11000000
		else
			load_address=81000000
		fi
		image_name="zImage_${cpu_arch}"
		TARGET_NAME="${IMAGE}_signed"
		printf "zImage detected!\n"
	elif [ "$MAGIC_NUMBER_DEVTREE_FIT_IMAGE" == "edfe0dd0" ]; then
		# set global variables
		if [ "$cpu_arch" == "sdq" ]; then
			load_address=12000000
		elif [ "$cpu_arch" == "8mm" ]; then
			load_address=43000000
		elif [ "$cpu_arch" == "8mn" ]; then
			load_address=43000000
		elif [ "$cpu_arch" == "8mp" ]; then
			load_address=43100000
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
		TARGET_NAME="${IMAGE}_signed"
	elif [ "$MAGIC_NUMBER_E" == "43454345" ] || \
			[ "$MAGIC_NUMBER_M4" == "4d344d34" ]; then
		printf "E-Boot/M4 image not yet supported! Aborting....\n"
		rm -r $TMP_DIR
		exit 1
	elif [ "$MAGIC_NUMBER_FS" == "584c5346" -a \
           "$MAGIC_NUMBER_FS_IMAGE_TYPE" == "4f4f424e"   ]; then
		image_name="nboot_${cpu_arch}"
		TARGET_NAME="${image_name}_signed.fs"
		if [ "$cpu_arch" == "8mm" ]; then
			load_address=7E0FC0
			download_addr=40480000
			test_addr=00920000
			tee_addr=56000000
		elif [ "$cpu_arch" == "8mn" ]; then
			load_address=00921fc0
			download_addr=40480000
			test_addr=00960000
			tee_addr=56000000
		elif [ "$cpu_arch" == "8mp" ]; then
			load_address=00927fc0
			download_addr=40480000
			test_addr=00968000
			tee_addr=56000000
		fi
		is_imx8m_nboot=1
	elif [ "$MAGIC_NUMBER_FS" == "584c5346" -a \
           "$MAGIC_NUMBER_FS_IMAGE_TYPE" == "52414f42"   ]; then
		image_name="nboot_${cpu_arch}"
		TARGET_NAME="${image_name}_signed.fs"
		if [ "$cpu_arch" == "8mm" ]; then
			load_address=7E0FC0
			download_addr=40480000
			test_addr=00920000
			tee_addr=56000000
		elif [ "$cpu_arch" == "8mn" ]; then
			load_address=00921fc0
			download_addr=40480000
			test_addr=00960000
			tee_addr=56000000
		elif [ "$cpu_arch" == "8mp" ]; then
			load_address=0091ffc0
			download_addr=40480000
			test_addr=00968000
			tee_addr=56000000
		fi
		is_imx8m_nboot=1
	elif [ "$MAGIC_NUMBER_FS" == "584c5346" -a \
           "$MAGIC_NUMBER_FS_IMAGE_TYPE" == "4f422d55" ]; then
		printf "i.MX8M uboot detected\n"
		image_name=uboot
		TARGET_NAME="${image_name}_${cpu_arch}_signed.fs"
		load_address=401fffc0
		is_imx8m_uboot=1
	elif [ "$MAGIC_NUMBER_AARCH64_ZIMAGE" == "644d5241" ]; then
		printf "Kernel Image detected\n"
		image_name="Image_${cpu_arch}"
		TARGET_NAME="${IMAGE}_signed"
		load_address=40480000
	else
		printf "Image type not supported! Aborting....\n"
		rm -r $TMP_DIR
		exit 1
	fi

	if [ -n "$custom_load_address" ]; then
		if [[ $is_imx8m_nboot -eq 1 ]]; then
			download_addr=$custom_load_address
		else
			load_address=$custom_load_address
		fi
	fi
}

###############################################################################
# function: createSignedImage()
#
# parameters: -
#
# return:     -
#
# description:
# This function sets all the remaining wildcards in the $BOOT_IN_CSF variable.
# and runs the cst tool to generate a signed image. Warning, TARGET is a global
# variable!!
#
###############################################################################
function createSignedImage()
{
	local load_address_hex=0x"$load_address"
	local image_size=$(stat -c %s "$TMP_DIR/$IMAGE")
	local signing_address="$load_address_hex"
	local signing_size="$image_size"
	local signing_offset=0x0
	image_size=0x`printf "%08x" "$image_size"`
	#image_size=$(($image_size - 0x100))

	if [ -z $1 ]; then
		exit_early=0
	else
		exit_early=$1
	fi

	if [[ "$image_name" == *"nboot"* ]]; then
		# signing begins at offset 0x14
		signing_offset=0x14

		# get offset where signature must be located. This is also the length
		# of the image without signature.
		image_size=`grep -a -o -b "##CSF##" "$TMP_DIR/$IMAGE" | \
				sed -e "s/:.*//"`
		# cut NBoot image at ###CSF###
		truncate -s $image_size $TMP_DIR/$IMAGE
		if [ "$?" != "0" ]; then
			printf "\nFunction createSignedImage() failed! Aborting....\n\n"
			rm -r $TMP_DIR
			return 1
		fi
		# convert image_size to hex value
		image_size=0x`printf "%x" "$image_size"`

		# signing size begins at offset signing_offset till end of image
		let signing_size="$image_size - $signing_offset"
		# convert to size in hex
		signing_size=0x`printf "%x" "$signing_size"`
	fi

	# setup signing_address
	let signing_address="$load_address_hex + $signing_offset"
	signing_address=0x`printf "%x" "$signing_address"`
	sed -e "s/###ADDR###/$signing_address/" \
		-e "s/###OFFSET###/$signing_offset/" -e "s/###SIZE###/$signing_size/" \
		-e "s|###BOOT###|$TMP_DIR/$IMAGE|" -e "s/###ENGINE###/$engine/" \
		$TMP_DIR/$BOOT_IN_CSF > $TMP_DIR/$BOOT_IN_CSF_FAKE
	if [[ "$image_name" == *"nboot"* ]]; then
		sed -e "23 s/#//" -e "24 s/#//" $TMP_DIR/$BOOT_IN_CSF_FAKE > \
		$TMP_DIR/$BOOT_IN_CSF
	else
		sed -e "25 s/#//" $TMP_DIR/$BOOT_IN_CSF_FAKE > \
		$TMP_DIR/$BOOT_IN_CSF
	fi
	#
	#less $TMP_DIR/$BOOT_IN_CSF

	# generate no output on stdout
	$CST_BINARY --o $TMP_DIR/$CSF_BIN --i $TMP_DIR/$BOOT_IN_CSF > /dev/null
	if [ "$?" != "0" ]; then
		printf "\nCan not create signature! Aborting....\n\n"
		rm -r $TMP_DIR
		return 1
	fi

	if [[ -n "$OUTPUT_NAME" ]] && [[ $is_imx8m_nboot -ne 1 ]]; then
		TARGET_NAME="$OUTPUT_NAME"
	fi

	# merge image + signature together
	cat $TMP_DIR/$IMAGE $TMP_DIR/$CSF_BIN > $TMP_DIR/${TARGET_NAME}_t
	mv $TMP_DIR/${TARGET_NAME}_t $TMP_DIR/${TARGET_NAME}

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
	#hexdump -e '4/4 "%08x ""\n"' $TMP_DIR/$TARGET_NAME |less

	# create bin folder if not exists
	mkdir -p bin
	# delete temp files if possible
	if [[ $exit_early == 0 ]]; then
		cp $TMP_DIR/$TARGET_NAME bin
		rm -r $TMP_DIR
	fi

	return 0
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
	local ivt_header=412000D1
	local IVT_TARGET=`echo "${image_name}_ivt.bin"`
	local image_size=$(stat -c %s "$TMP_DIR/$IMAGE")
	local csf_absolute_addr=0
	local ZEROS=00000000
	local boot_data_absolute_addr=0
	local entry_point_addr=0
	local self_addr=0

	if [ -z $1 ]; then
		offset=0
	else
		offset=$1
	fi

	let boot_data_absolute_addr="0x$load_address + 0x20 + $offset"
	let self_addr="0x$load_address + $offset"

	if [ -z $2 ]; then
		let entry_point_addr="0x$load_address + 0x40 + $offset"
		image_size=`printf "%d "$(($image_size-32))`
	else
		let entry_point_addr="0x$load_address"
		image_size=`printf "%d "$(($image_size+32))`
	fi

	image_size=`printf "%08x" $image_size`
	boot_data_absolute_addr=$(printf "%08x" $boot_data_absolute_addr)
	entry_point_addr=$(printf "%08x" $entry_point_addr)
	self_addr=$(printf "%08x" $self_addr)
	csf_absolute_addr=`printf "%08x" $((0x$image_size+0x$entry_point_addr))`

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
	# normally: selfpointer = load_address, because ivt have no offset
	# i.MX8 N-Boot: selfpointer = load_addr + 0x40 because of the FS-Header
	# change big endians to little endians
	temp=`echo ${self_addr:6:2}${self_addr:4:2}${self_addr:2:2}\
${self_addr:0:2}`
	# insert \x every Byte so it can be interpreted as a binary file
	out=`echo -n -e $temp | sed -e 's/.\{2\}/&\\\x/g'`
	# insert \x at the beginning
	temp=\\x$out
	# remove \x at the end
	final=${temp::-2}
	echo -n -e $final >> $TMP_DIR/$IVT_TARGET

	### -> CSF <- ###
	# in createBootDataHeader the image itself is merged with boot_data_header
	# so if we stat the image here the $image_size => sizeof image +
	# boot_data-header so we have subtract the boot_data_header to get the real
	# image size. Boot_data_header has a fix size 0x20 => 32 (decimal).
	# For most i.MX8 N-Boot Images, the length is considered as the original
	# Image length.

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
	#hexdump -C $TMP_DIR/$IMAGE | less

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

	#hexdump -e '1/4 "start:       %08x\n"
    #            1/4 "length:      %08x\n"
    #            1/4 "plugin flag: %08x\n"
#				1/20 "...:         %s\n"' $TMP_DIR/$BOOT_DATA_HEADER

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
				-e "s/###ENGINE###/$engine/" -e "25 s/#//" \
				"$TMP_DIR/$BOOT_IN_CSF" > "$TMP_DIR/$BOOT_IN_CSF_FAKE"

			# suppress output generated by the cst tool
			cp $TMP_DIR/$BOOT_IN_CSF_FAKE $BOOT_IN_CSF_FAKE
			$CST_BINARY --o $TMP_DIR/$CSF_BIN --i $TMP_DIR/$BOOT_IN_CSF_FAKE \
			1>/dev/null
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
			# setup as hex number
			signed_image_length=`printf "%08x" $signed_image_length`
			if [ $image_name == spl ]; then
				signed_image_length=$(printf "%08x" \
				$((0x$signed_image_length + 0x400)))
			fi
	    ;;
	esac
}

###############################################################################
# function: adjustField()
#
# parameters: $1 --> Input File
#             $2 --> offset in file
#             $3 --> 4 Byte Value to write (hex without 0x in front)
#
# return:     -
#
# description:
# This function is used to change out 32 bit words in a file with a new one.
# It is intended, but not limited, for use with FS-Headers or IVT structures.
#
# TODO: Currently the function uses the 'dd' function, which works, but is
# slow. If there is a faster way, it may be implemented.
#
###############################################################################
function adjustField
{
	INPUT_FILE=$1
	start=$2
	end=$(($2+$field_size))
	value=$3

	value=$(printf "%s%s%s%s" \
		${value:6:2} ${value:4:2} ${value:2:2} ${value:0:2} | \
		sed -e 's/.\{2\}/\\\x&/g')

	dd if=${INPUT_FILE} of=${INPUT_FILE}_low bs=4 count=$(($start/4)) status=none
	dd if=${INPUT_FILE} of=${INPUT_FILE}_high bs=4 skip=$(($end/4)) status=none
	echo -n -e $value >> ${INPUT_FILE}_low
	cat ${INPUT_FILE}_low ${INPUT_FILE}_high > $INPUT_FILE
}

###############################################################################
# function: saveEnvironment()
#
# parameters: global variables
#             --> image_name
#             --> IMAGE
#             --> TARGET_NAME
#
# return:     global variables
#             --> image_name_back
#             --> IMAGE_back
#             --> TARGET_NAME_back
#
# description:
# This function makes backup saves for certain variables, that need to be
# changed during the signing process of the i.MX8 N-Boot. They contain
# Information about the Input Image and the Target Image. The original Variables
# are used by createSignedImage(). Because the signing Process needs to sign the
# sub-Images, it needs to change them up frequently. So this backup is necessary
# for later use.
#
###############################################################################
function saveEnvironment
{
	image_name_back=$image_name
	IMAGE_back=$IMAGE
	TARGET_NAME_back=$TARGET_NAME
}

###############################################################################
# function: PrepearEnvironment()
#
# parameters: $1 --> Name of the Image to be signed next.
#
# return:     global variables
#             --> image_name
#             --> IMAGE
#             --> TARGET_NAME
#
# description:
# This function sets up the Image and Target Variables for
# create_signed_image()
#
###############################################################################
function PrepearEnvironment
{
	image_name=$1
	IMAGE=$1
	TARGET_NAME=$1"_signed"
}

###############################################################################
# function: restoreEnvironment()
#
# parameters: global variables
#             --> image_name
#             --> IMAGE
#             --> TARGET_NAME
#
# return:     global variables
#             --> image_name_back
#             --> IMAGE_back
#             --> TARGET_NAME_back
#
# description:
# This function restores the saved environment, with the backup that has been
# created in saveEnvironment()
#
###############################################################################
function restoreEnvironment
{
	image_name=$image_name_back
	IMAGE=$IMAGE_back
	TARGET_NAME=$TARGET_NAME_back
}

###############################################################################
# function: fsImageGetSizeAndOffset()
#
# parameters: $1 --> type of the current header
#
#             global Variables
#             --> TMP_DIR
#             --> IMAGE
#             --> TARGET_NAME
#
# return:     dynamically named variables
#             --> $1_size
#             --> $1_offset
#
# description:
# This function reads the size out of the next FS-Header in IMAGE for later
# use. It also reads the current size of TARGET_NAME, so the Image can be found
# later again in TARGET_IMAGE without the need for another calculation. This
# way, the size field of the FS-Header can be adjusted, if needed later on more
# easily.
#
###############################################################################
function fsImageGetSizeAndOffset
{
	printf -v "${1}_size" '%d' 0x$(hexdump -v -s $fs_image_size_low -n \
		$field_size -e'1/8 "%X"' $TMP_DIR/$1)

	if [ -f $TMP_DIR/$TARGET_NAME ]; then
		printf -v "${1}_offset" '%d' $(stat --printf=%s $TMP_DIR/$TARGET_NAME)
	else
		printf -v "${1}_offset" '%d' 0
	fi
}

###############################################################################
# function: getNextFSHeaderAndImage()
#
# parameters: $1 --> type of the current Image
#
# return:     -
#
# description:
# This is a legacy function that does not serve its original purpose. It will
# be removed at a later date.
#
###############################################################################
function getNextFSHeaderAndImage
{
	PrepearEnvironment $1
}

###############################################################################
# function: FSImageAppendIVT()
#
# parameters: $1 --> type of the current Image
#
#             global Variables
#             --> TMP_DIR
#
# return:     -
#
# description:
# This function is used to add IVT and Bootdata structure between the Header and
# the Image. Both must exist in two different files beforehand. Afterwards a
# single file with no extension to the type name will be in the temp directoy
# including thenew structures
#
###############################################################################
function FSImageAppendIVT
{
	createBootDataHeader
	createIVTHeader $header_size
}

###############################################################################
# function: getFSImageSignedSizeAndDiff()
#
# parameters: $1 --> type of the current Image
#
# return:     global variables:
#             --> length_no_header
#             --> signed_image_size (runFakeCST)
#             --> $1_size_diff
#
# description:
# This function is used to get several sizes, used by other functions
#
# NOTE: runFakeCST() call is necessary because the header fields need this
# information BEFORE the actual signing process
#
###############################################################################
function getFSImageSignedSizeAndDiff
{
	local size="$1"_size
	runFakeCST
	length_no_header=$(printf "%08X" \
		$((0x$signed_image_length - $header_size)))
	printf -v "$1_size_diff" '%d' $((0x$length_no_header - ${!size}))
}

###############################################################################
# function: setFSImageAndIVTLengthFields()
#
# parameters: $1 --> current Image
#
#             global variables:
#             --> TMP_DIR
#
# return:     -
#
# description:
# This function sets the length field in both boot the IVT and the FS-Header
# of the current Image.
#
###############################################################################
function setFSImageAndIVTLengthFields
{
	local size="$1"_size
	adjustField $TMP_DIR/"$1" $(($header_size + $boot_data_length)) \
		$(printf "%08X" ${!size})
	adjustField $TMP_DIR/"$1" $fs_image_size_low  $length_no_header
}

###############################################################################
# function: ivtToFSImage()
#
# parameters: $1 --> current Image
#             $2 -->
#             $3 --> load_address
#
# return:     -
#
# description:
# Adds an IVT to an FS-Image
#
###############################################################################
function ivtToFSImage
{
	getNextFSHeaderAndImage $2
	load_address=$3
	FSImageAppendIVT $2
	restoreEnvironment
}

###############################################################################
# function: xtractNextImage()
#
# parameters: global variables
#             --> full_size
#             --> TMP_DIR
#             --> IMAGE
#             --> fs_index
#
# return:     -
#
# description:
# gets next Image and Header and saves the files in the TMP_DIR
#
###############################################################################
function xtractNextImage
{
	full_size=$((0x"${list[$(($(($fs_index*2))+1))]}"))

	local skip=$((0x"${list[$(($fs_index*2))]}"))
	local count=$(($full_size+0x40))

	local s2=$(($skip/16))
	local c2=$(($count/16))
	
	dd if=_tmp/$IMAGE of=_tmp/temp bs=16 skip=$s2 count=$c2 status=none
	dd if=_tmp/temp of=$TMP_DIR/header bs=64 count=1 status=none
	dd if=_tmp/temp of=$TMP_DIR/body bs=64 skip=1 status=none
}

###############################################################################
# function: get_sizes()
#
# parameters: $1: remaining bytes
#             $2: array to save values to
#             global variables
#             --> remaining
#             --> TMP_DIR
#             --> size
#             local variables
#             --> temp
#
# return:     -
#
# description:
# gets sizes of the Image group and recurses through the group
#
# TODO: $2 is always the same, can be removed
#
###############################################################################
function get_sizes
{
	remaining=$1
	local -n temp=$2
	while [ $remaining -gt 0 ]; do
		size=$(tail -c $remaining $TMP_DIR/temp | ./fsimage.sh -s size)
		remaining=$(($remaining - $size - 0x40))
		temp+=( $size )
	done
}

###############################################################################
# function: get_types()
#
# parameters: $1: remaining bytes
#             $2: array to save values to
#             global variables
#             --> remaining
#             --> type
#             --> TMP_DIR
#             --> sizes
#             --> s
#             local variables
#             --> temp
#
# return:     -
#
# description:
# gets types of the Image group and recurses through the group
#
# TODO: $2 is always the same, can be removed
#
###############################################################################
function get_types
{
	remaining=$1
	local -n temp=$2
	for s in ${sizes[@]}; do
		type=$(tail -c $remaining $TMP_DIR/temp | ./fsimage.sh -s type)
		remaining=$(($remaining - $s - 0x40))
		temp+=( $type )
	done
}

###############################################################################
# function: cycle_subimages()
#
# parameters: $1: Image
#             global variables
#             --> full_size
#             --> fs_index
#             --> TMP_DIR
#             local variables
#             --> sizes
#             --> types
#             --> t
#
# return:     -
#
# description:
# gets Information about the Image group and recurses through the group
#
###############################################################################
function cycle_subimages
{
	local sizes
	local types
	local t

	get_sizes $full_size sizes
	get_types $full_size types

	for t in ${types[@]}; do
		fs_index=$(($fs_index + 1))
		signiMX8NBoot $t
		touch $TMP_DIR/$1
		cat $TMP_DIR/$t >> $TMP_DIR/$1
		rm $TMP_DIR/$t
	done
}

###############################################################################
# function: get_fs_image_traits()
#
# parameters: $1: Path to Image
#             $2: index of the current thread
#             global variables
#             --> addr
#             --> free
#             --> current_flags
#             --> descr
#             --> type
#             --> flags
#             --> org_size
#
# return:     -
#
# description:
# gets information from current Image
#
###############################################################################
function get_fs_image_traits
{
	addr=$(./fsimage.sh -s p32[7] $1 $2)
	free=$(./fsimage.sh -s p8[27] $1 $2)
	type=$(./fsimage.sh -s type  $1 $2)
	descr=$(./fsimage.sh -s descr  $1 $2)
	flags=$(./fsimage.sh -s flags $1 $2)
	org_size=$(printf "%08x" $(./fsimage.sh -s size  $1 $2))
}

###############################################################################
# function: handleImageGroup()
#
# parameters: $1: Current image type
#             $2: full image size
#			  $3: index of the current thread
#             global variables
#             --> TMP_DIR
#             --> IMAGE
#             --> current_flags
#             --> descr
#             --> type
#             --> flags
#             --> FSH_FLAGS_CRC32
#             local variables
#             --> my_index
#             --> full_size
#
# return:     -
#
# description:
# called for FS-Images that contain a group
#
###############################################################################
function handleImageGroup
{
	local full_size=$2
	local my_index=$3

	cycle_subimages $1

	get_fs_image_traits $TMP_DIR/header_${my_index} 0
	if [ $(($flags & $FSH_FLAGS_CRC32)) -ne 0 ]; then
		./addfsheader.sh -q -d $descr -t $type $TMP_DIR/$1 > $TMP_DIR/$1_header
	else
		./addfsheader.sh -q -d $descr -t $type -s $TMP_DIR/$1 > $TMP_DIR/$1_header
	fi
	mv $TMP_DIR/$1_header $TMP_DIR/$1
	current_flags=$(./fsimage.sh -s flags $TMP_DIR/$IMAGE $my_index)
}

###############################################################################
# function: handleFSImage()
#
# parameters: $1: type of current Image
#             $2: index of the current thread
#             global variables
#             --> TMP_DIR
#             --> BOOT_IN_CSF
#             --> current_flags
#             --> descr
#             --> type
#             local variables
#             --> my_index
#
# return:     -
#
# description:
# called for FS-Images that contain a single Image instead of a group
#
###############################################################################
function handleFSImage
{
	local my_index=$2
	current_flags=$(./fsimage.sh -s flags _tmp/header 0)
	if ! [ $(($current_flags & 0x4000)) -eq 0 ]; then
		signFSImage $1 $my_index
	else
		get_fs_image_traits $TMP_DIR/$IMAGE $my_index
		./addfsheader.sh -a 16 -q -d $descr -t $type $TMP_DIR/body > $TMP_DIR/new_header
		mv $TMP_DIR/new_header $TMP_DIR/$type
	fi
}

###############################################################################
# function: signFSImageInEnvironment()
#
# parameters: --> TMP_DIR
#             --> BOOT_IN_CSF
#
# return:     -
#
# description:
# this method is considered legacy and will be removed or repurposed in the
# future
#
###############################################################################
function signFSImageInEnvironment
{
	PrepearEnvironment new_header

	fsImageGetSizeAndOffset new_header
	getFSImageSignedSizeAndDiff new_header
	setFSImageAndIVTLengthFields new_header

	cp $TMP_DIR/$BOOT_IN_CSF $TMP_DIR/boot_in_org
	createSignedImage exit_early
	cp $TMP_DIR/boot_in_org $TMP_DIR/$BOOT_IN_CSF

	restoreEnvironment
}

###############################################################################
# function: getNewFsHeader()
#
# parameters: $1: Image body to append header to
#             global variables
#             --> TMP_DIR
#             --> addr
#             --> IMAGE
#             --> type
#             --> my_index
#             --> addr_base10
#             --> descr
#
# return:     -
#
# description:
# create new FS-Header for the Image to be signed.
# TODO: my_index should be local but it does work anyways.
# TODO: $1 is always the same, can be removed
#
###############################################################################
function getNewFsHeader
{
	get_fs_image_traits _tmp/header 0
	addr_base10=$(printf "%d" 0x$addr)
	./addfsheader.sh -a 16 -q -d $descr -t  $type $TMP_DIR/$1 > $TMP_DIR/new_header
}

###############################################################################
# function: sign_spl()
#
# parameters: global variables
#             --> TMP_DIR
#             --> addr
#             --> org_size
#             --> type
#
# return:     -
#
# description:
# signs an SPL for use in a NBoot
#
###############################################################################
function sign_spl
{
	length=$(stat -c %s _tmp/body)
	if [[ "$cpu_arch" == "8mm" ]]; then
		self=$(hexdump -v -s 0x14 -n $field_size -e'1/8 "%X"' $TMP_DIR/body)
		csf=$(hexdump -v -s 0x18 -n $field_size -e'1/8 "%X"' $TMP_DIR/body)
		real_size=$((0x$csf - 0x$self))
		dd if=_tmp/body of=_tmp/spl_no_padding count=$((real_size)) status=none bs=1
	else
		dd if=_tmp/body of=_tmp/spl_no_padding count=$(($length - 0x2000)) status=none bs=1
	fi

	PrepearEnvironment spl_no_padding
	cp $TMP_DIR/$BOOT_IN_CSF $TMP_DIR/boot_in_org
	createSignedImage exit_early
	cp $TMP_DIR/boot_in_org $TMP_DIR/$BOOT_IN_CSF
	restoreEnvironment

	if [[ "$cpu_arch" == "8mm" ]]; then
		bd_length=$(hexdump -v -s 0x24 -n $field_size -e'1/8 "%X"' $TMP_DIR/body)
		image_length=$(printf %x $((0x$bd_length - 0x400)))
		dd if=/dev/zero  of=$TMP_DIR/spl_no_padding_signed bs=1 seek=$(stat -c %s $TMP_DIR/spl_no_padding_signed) count=$((0x$image_length - $(stat -c %s $TMP_DIR/spl_no_padding_signed))) status=none
	else
		dd if=/dev/zero  of=$TMP_DIR/spl_no_padding_signed bs=1 seek=$(stat -c %s $TMP_DIR/spl_no_padding_signed) count=4288 status=none
	fi
	./addfsheader.sh -a 16 -q -d "fsimx"${cpu_arch} -t "SPL" -f 0xe000 -c -s -p32[7]=0x00922000 $TMP_DIR/spl_no_padding_signed > $TMP_DIR/$type
}

###############################################################################
# function: sign_fs_subimage()
#
# parameters: global variables
#             --> TMP_DIR
#             --> length
#             --> BOOT_IN_CSF
#             --> type
#
# return:     -
#
# description:
# signs an FS Image with its Header Information
#
###############################################################################
function sign_fs_subimage
{
	ivtToFSImage header body $addr
	adjustField _tmp/body 36 $org_size
	getNewFsHeader body
	signFSImageInEnvironment
	mv $TMP_DIR/new_header_signed $TMP_DIR/$type
	adjustField $TMP_DIR/$type 12 "1000e000"
	adjustField $TMP_DIR/$type 28 $(crc32 $TMP_DIR/$type)
}

###############################################################################
# function: signFSImage()
#
# parameters: --> $1: type of current Image
#             --> $2: index of current thread
#             global variables
#             --> TMP_DIR
#             --> IMAGE
#             local variables
#             --> my_index
#
# return:     -
#
# description:
# checks if the current subimage is an SPL or not. Depending to the result the
# Image will be signed accordingly.
#
###############################################################################
function signFSImage
{
	local my_index=$2
	get_fs_image_traits _tmp/header 0
	sync
	value=$(head -c 1 _tmp/body | xxd -p)
	if [[ "$value" != "d1" ]]; then
		sign_fs_subimage
	else
		sign_spl
	fi
}

###############################################################################
# function: check_type_and_handle()
#
# parameters: --> $1: type of subimage
#             --> $2: full size of subimage
#             --> $3: fs_index of the current thread
#             global variables
#             --> TMP_DIR
#             --> full_size
#             local variables
#             --> my_index
#
# return:     -
#
# description:
# checks if the current Image is a grouping Image or a single one.
# TODO: can be checked with the flags, maybe more performent.
#
###############################################################################
function check_type_and_handle
{
	full_size=$2
	my_index=$3

	get_fs_image_traits _tmp/header 0
	cp _tmp/header _tmp/header_${my_index}

	./fsimage.sh -l $TMP_DIR/body &> /dev/null
	if [ $? -eq 0 ]; then
		load_spaces=$load_spaces"-"
		handleImageGroup $1 $full_size $my_index
		load_spaces=${load_spaces::-1}
	else
		handleFSImage $1 $my_index
	fi
	echo $load_spaces"> $type signed"
}

###############################################################################
# function: signiMX8NBoot()
#
# parameters: --> $1: type of subimage
#             global variables
#             --> TMP_DIR
#             --> fs_index
#             --> name
#             --> full_size
#             local variables
#             --> my_index
#
# return:     -
#
# description:
# extracts the current subindex. The Image is the one with the Index saved in
# fs_index. Afterwards the Image gets checked for the Secure Flag and handled
# depending on the result.
#
###############################################################################
function signiMX8NBoot
{
	saveEnvironment
	local my_index=$fs_index

	xtractNextImage

	if [ $(($(./fsimage.sh -s flags $TMP_DIR/header) & 0x2000)) -eq 0 ]; then
		name=$(./fsimage.sh -s type $TMP_DIR/header)
		cat $TMP_DIR/header $TMP_DIR/body > $TMP_DIR/$name
		return
	fi

	check_type_and_handle $1 $full_size $my_index
}

###############################################################################
# function: prepare_uboot()
#
# parameters: globale variablen
#             -> TMP_DIR
#             -> IMAGE
#             -> uboot_size
#             -> image_name
#             -> image_name_back
#             -> fs_image_size_low
#
# return:     -
#
# description:
# Prepares UBoot Image for signing.
#
###############################################################################
function prepare_uboot
{
	image_name_back=$image_name
	image_name=u-boot

	dd if="${TMP_DIR}/${IMAGE}" of="${TMP_DIR}/${IMAGE}_image" \
		bs=1 skip=$header_size status=none

	cp ${TMP_DIR}/${IMAGE}_image ${TMP_DIR}/${IMAGE}

	createBootDataHeader
	createIVTHeader 0x40

	./addfsheader.sh -a 16 -q -d "fsimx"${cpu_arch} -t "U-BOOT" $TMP_DIR/$IMAGE > $TMP_DIR/${IMAGE}_new
	cp $TMP_DIR/${IMAGE}_new $TMP_DIR/$IMAGE

	uboot_size=$(printf "%08x" $(($(stat --printf=%s $TMP_DIR/$IMAGE) + 0xF48 - 0x40)))
	adjustField $TMP_DIR/$IMAGE $fs_image_size_low $uboot_size
}

###############################################################################
# function: finish_uboot()
#
# parameters: globale variablen
#             -> TMP_DIR
#             -> TARGET_NAME
#             -> OUTPUT_NAME
#             -> image_name
#             -> image_name_back
#             -> LIGHT_GREEN
#             -> NORMAL
#
# return:     -
#
# description:
# does last touches on the UBoot Image before it can be installed.
#
###############################################################################
function finish_uboot
{
	adjustField $TMP_DIR/$TARGET_NAME 12 "1000e000"
	adjustField $TMP_DIR/$TARGET_NAME 28 $(crc32 $TMP_DIR/$TARGET_NAME)

	cp $TMP_DIR/$TARGET_NAME bin/$OUTPUT_NAME

	if [[ -n $OUTPUT_NAME ]]; then
		TARGET_NAME=$OUTPUT_NAME
	fi

	image_name=$image_name_back

	printf "${LIGHT_GREEN}Signed image (%s) successfully generated. ${NORMAL}\b\n" "$TARGET_NAME"
	rm -r $TMP_DIR
}

###############################################################################
# function: signImx8Uboot()
#
# parameters: -
#
# return:     -
#
# description:
# handles to workflow of signing the UBoot for i.MX8M Boards.
#
###############################################################################
function signImx8Uboot
{
	prepare_uboot
	createSignedImage exit_early
	finish_uboot
}

###############################################################################
# function: setup_tool()
#
# parameters: local variables
#             -> @ (list of parameters)
#
# return:     -
#
# description:
# set up the environment of the tool with the values given by the makeaction.sh
# script
#
###############################################################################
function setup_tool
{
	handleParameters "$@"
	setup_variables
	setCertNumberSigning
	getImageToBeSigned
	getImageType
}

function get_offsets_and_sizes
{
	local string=$(./fsimage.sh -l $TMP_DIR/$IMAGE | sed -e 's/^.*: //g' | sed -e 's/ D.*//g' | sed -e '/^[- ]/d')
	string=$(echo $string | tr '\n' ' ')
	read -a list <<< "$string"

	for i in $list; do
		echo $I
	done
}

###############################################################################
# function: start_sign_imx8m_nboot()
#
# parameters: global variables
#             -> TARGET_NAME
#             -> TMP_DIR
#
# return:     does not return
#
# description:
# Starting point to sign an i.MX8M NBoot Container. Calls the recursive signing
# system and finishes the process by adding the saving Signature.
#
###############################################################################
function start_sign_imx8m_nboot
{
	get_offsets_and_sizes
	signiMX8NBoot NBOOT
	cp $TMP_DIR/NBOOT bin/${TARGET_NAME}_recovery
	./fsimage.sh -x $TMP_DIR/NBOOT 0 > $TMP_DIR/NBOOT_no_header
	ivtToFSImage none NBOOT_no_header "40480000"
	dd if=$TMP_DIR/$IMAGE of=$TMP_DIR/header bs=64 count=1 status=none
	getNewFsHeader NBOOT_no_header
	signFSImageInEnvironment
	mv $TMP_DIR/new_header_signed $TMP_DIR/$TARGET_NAME
	adjustField $TMP_DIR/$TARGET_NAME 12 "1000e000"
	mv $TMP_DIR/$TARGET_NAME bin/$TARGET_NAME

	printf "${LIGHT_GREEN}Signed image (%s) successfully generated. ${NORMAL}\b\n" "$TARGET_NAME"
}

###############################################################################
# function: sign_imx8m_image()
#
# parameters: global variables
#             -> is_imx8m_nboot
#             -> is_imx8m_uboot
#             -> TMP_DIR
#
# return:     does not return
#
# description:
# handles signing process for fs Images affiliated with Boards using the i.MX8M
# processor types.
#
###############################################################################
function sign_imx8m_image
{
	if [ ! -z $is_imx8m_nboot ]; then
		start_sign_imx8m_nboot
		rm -r $TMP_DIR
		exit 0
	fi
	if [ ! -z $is_imx8m_uboot ]; then
		signImx8Uboot
		exit 0
	fi
}

###############################################################################
# function: sign_imx6_or_linux_image()
#
# parameters: global variables
#             -> image_name
#             -> TARGET_NAME
#             -> TMP_DIR
#             -> NORMAL
#             -> LIGHT_RED
#             -> LIGHT_GREEN
#
# return:     does not return
#
# description:
# handles signing process for older Image types from the 32 bit Systems or more
# simple Images like the Linux Kernel and Devicetree
#
###############################################################################
function sign_imx6_or_linux_image
{
	if [[ "$image_name" != *"nboot"* ]]; then
		createBootDataHeader
		createIVTHeader
	fi

	createSignedImage
	if [ "$?" == "0" ]; then
		printf "${LIGHT_GREEN}Signed image (%s) successfully generated.
		${NORMAL}\b\n" "$TARGET_NAME"
		exit 0
	else
		printf "\n${LIGHT_RED}Error, aborting...${NORMAL}\b\n"
		exit 1
	fi
	printf "${LIGHT_GREEN}Signed image (%s) successfully generated. ${NORMAL}\b\n" "$TARGET_NAME"
	rm -r $TMP_DIR

	exit 0
}

# main function
fs_index=0
setup_tool "$@"
sign_imx8m_image			#no return
sign_imx6_or_linux_image	#no return
