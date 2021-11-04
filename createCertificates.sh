#!/bin/bash


###############################################################################
# function: handleParameters()
#
# parameters: all parameters given to the script
#
# return: -
#
# description:
# This functions stores the script parameters in global(!) variables. Big
# letter variables are files/directories, small letter variables are just
# variables.
#
###############################################################################
function handleParameters()
{
	CST_DIR=$1
	SRKTOOL_BINARY=$2
}


###############################################################################
# function: setup_variables
#
# parameters:
#
# return: -
#
# description:
# Setup some environment variables
#
###############################################################################
function setup_variables()
{
	# create folder '_tmp' which contains all created temporary files and the
	# corresponding global variable
	TMP_DIR=_temp
	mkdir -p $TMP_DIR

	# get path to crts folder
	CRTS_DIR=`find ${CST_DIR} -type d -iname "crts"`
	if [ ! -d "$CRTS_DIR" ]; then
		printf "\ncrts folder not found! Aborting....\n\n"
		exit 1
	fi
	# get path to keys folder
	KEYS_DIR=`find ${CST_DIR} -type d -iname "keys"  | tail -n 1`
	if [ ! -d "$KEYS_DIR" ]; then
		printf "\nkeys folder not found! Aborting....\n\n"
		exit 1
	fi
}


###############################################################################
# function: check_serial
#
# parameters:
#
# return: 0: serial and passphrase don't exit
#         1: serial and passphrase exist
#
# description:
# Checks if the files serial and key_pass.txt already created.
#
###############################################################################
function check_serial()
{
	if [ -f $KEYS_DIR/serial ] && [ -f $KEYS_DIR/key_pass.txt ]; then
		return 1
	else
		return 0
	fi
}


###############################################################################
# function: create_serial
#
# parameters:

# return:
#
# description:
# Creates the serial and key_pass.txt containing the serial number and the
# keys passphrease.
# Important note: openssl expect the given filenames!
###############################################################################
function create_serial()
{
	printf "\nPlease enter a serial number (8 digits!):"
	local serial
	read serial
	# create file serial which contains input from user
	echo $serial > $TMP_DIR/serial
	# count digits
	characters=`printf $serial | wc -m`
	if [ $characters == 8 ] ; then
		cp $TMP_DIR/serial $KEYS_DIR/
	else
		rm -r $TMP_DIR
		printf "\ndigits: $characters != 8, Aborting....\n\n"
		exit 1
	fi

	printf "Please enter a passphrase (no blanks!):"
	local passPhrase
	read passPhrase
	# check for blanks
	echo $passPhrase > $TMP_DIR/key_pass.txt
	echo $passPhrase >> $TMP_DIR/key_pass.txt
	cp $TMP_DIR/key_pass.txt $KEYS_DIR/
}


###############################################################################
# function: check_Certificates()
#
# parameters: -
#
# return: 0: Certificates don't exist
#         1: Certificates exist
# description:
# Checks if the certificates already exist
###############################################################################
function check_Certificates()
{
	if [ `ls -l $CRTS_DIR/SRK*.pem 2>/dev/null | wc -l` -gt 0 ]; then
		printf "Certificates already exist!\n"
		return 1
	else
		return 0
	fi
}


###############################################################################
# function: create_Certificates()
#
# parameters: c: no default settings
#             d: default settings
# return: -
#
# description:
# Creates the certificates by running NXP's hab4_pki_tree.sh script
# Either with default settings or not (depending on the input parameters)
#
###############################################################################
function create_Certificates()
{
	# we have to switch inside the $KEYS_DIR to create certificates because
	# it copy the certificates to necessary crts/keys folder from its relativ
	# path.
	local home=$PWD
	cd $KEYS_DIR
	#check if hab4_pki_tree.sh exists
	if [ ! -f hab4_pki_tree.sh ]; then
		printf "\nhab4_pki_tree.sh does not exist! Aborting....\n\n"
		rm -r $TMP_DIR
		exit 1
	fi

	# call script from Code Signing Tool
	./hab4_pki_tree.sh 2>/dev/null          # generate no output on console
	if [ $? == "1" ]; then
		printf "\nFailed to create certificates! Aborting....\n\n"
		rm -r $TMP_DIR
		exit 1
	else
		printf "Certificate(s) sucessfully created\n"
	fi

	cd $home
}


###############################################################################
# function: createSRK()
#
# parameters: $1: number of certificates
#             $2: number of bits (1024, 2048, 4096)
#
# return: -
#
# description:
# This is a simple script for creating SRK table adn Fuse files.
#
###############################################################################
function createSRK()
{
	local key_length=0
	local flag=0
	local pattern=SRK1*.pem
	local file=`basename ${CRTS_DIR}/$pattern`
	local count=`ls -d ${CRTS_DIR}/SRK*.pem | wc -l`

	case "$file" in
		*1024*)
			key_length=1024
			;;
		*2048*)
			key_length=2048
			;;
		*3072*)
			key_length=3072
			;;
		*4096*)
			key_length=4096
			;;
		*)
			printf "\nKeylength not matched! Aborting....\n\n"
			rm -r $TMP_DIR
			exit 1
	esac

	# check if fast authentication?
	case "$file" in
		*_ca_*)
			flag="ca"
			;;
		*_usr_*)
			flag="usr"
			;;
		*)
			echo "\nFormat not known!, Aborting....\n\n"
			rm -r $TMP_DIR
			exit 1
	esac

	if [ "$count" = "1" ]; then
		$SRKTOOL_BINARY -h 4 -t $CRTS_DIR/SRK_Table.bin -e \
$CRTS_DIR/SRK_fuse.bin -d sha256 -c \
$CRTS_DIR/SRK1_sha256_${key_length}_65537_v3_${flag}_crt.pem -f 1
	elif [ "$count" = "2" ]; then
		$SRKTOOL_BINARY -h 4 -t $CRTS_DIR/SRK_Table.bin -e \
$CRTS_DIR/SRK_fuse.bin -d sha256 -c \
$CRTS_DIR/SRK1_sha256_${key_length}_65537_v3_${flag}_crt.pem,\
$CRTS_DIR/SRK2_sha256_${key_length}_65537_v3_${flag}_crt.pem -f 1
	elif [ "$count" = "3" ]; then
		$SRKTOOL_BINARY -h 4 -t $CRTS_DIR/SRK_Table.bin -e \
$CRTS_DIR/SRK_fuse.bin -d sha256 -c \
$CRTS_DIR/SRK1_sha256_${key_length}_65537_v3_${flag}_crt.pem,\
$CRTS_DIR/SRK2_sha256_${key_length}_65537_v3_${flag}_crt.pem,\
$CRTS_DIR/SRK3_sha256_${key_length}_65537_v3_${flag}_crt.pem -f 1
	elif [ "$count" = "4" ]; then
		$SRKTOOL_BINARY -h 4 -t $CRTS_DIR/SRK_Table.bin -e \
$CRTS_DIR/SRK_fuse.bin -d sha256 -c \
$CRTS_DIR/SRK1_sha256_${key_length}_65537_v3_${flag}_crt.pem,\
$CRTS_DIR/SRK2_sha256_${key_length}_65537_v3_${flag}_crt.pem,\
$CRTS_DIR/SRK3_sha256_${key_length}_65537_v3_${flag}_crt.pem,\
$CRTS_DIR/SRK4_sha256_${key_length}_65537_v3_${flag}_crt.pem  -f 1
	fi

	#modify boot_raw (CSF)
	sed -e "s/###BIT###/$key_length/" -e "s|###CST_DIR###|$CST_DIR|" \
	boot_raw > boot_raw_edited

	if [ "$?" != "0" ]; then
		printf "\nFunction createSRK() failed! Aborting ....\n\n"
		rm -r $TMP_DIR
		rm boot_raw_edited
		exit 1
	fi
}


###############################################################################
# function: createSRKHash()
#
# parameters: 0: SRK_fFuse.bin (absolute path)
#
# return: -
#
# description:
# Generates the srkhash based on the input (Fuse.bin). This function was
# implemented by Patrick Jakob (F&S Elektronik Systeme GmbH).
#
###############################################################################
function createSRKHash()
{
	local size_srk_fuse_bin=0
	local SRK_HASH_TXT="srkhash.txt"
	local SRK_FUSE_BIN="$CRTS_DIR/SRK_fuse.bin"
	if [ -z "$SRK_FUSE_BIN" ] ; then
		printf "\nSRK_fuse.bin not found! Aborting....\n\n"
		rm -r $TMP_DIR
		exit 1
	fi

	size_srk_fuse_bin=`stat -c %s "$SRK_FUSE_BIN"`
	if [ "$size_srk_fuse_bin"  == "32" ]; then
		local characters=`hexdump -v -e '/1 "%02X"' "$SRK_FUSE_BIN" | wc -c`
		if [ "$characters" == "64" ]; then
			hexdump -v -e '/1 "%02X"' "$SRK_FUSE_BIN" > $TMP_DIR/$SRK_HASH_TXT
			local srk_fuse=`cat $TMP_DIR/$SRK_HASH_TXT`
			local checksum=0
			local sum=0
			local i=1
			local byte_1=0
			local byte_2=0

			# create checksum
			while [ $i -le 16 ]
			do
				byte_1=`echo $srk_fuse | cut -b 1-2`
				byte_2=`echo $srk_fuse | cut -b 3-4`
				byte_1="0x"$byte_1""
				byte_2="0x"$byte_2""
				sum=`echo $(($byte_1 + $byte_2))`
				checksum=$((checksum+sum))
				srk_fuse=`echo ${srk_fuse:4}`
				i=$[i + 1]
			done

			# convert checksum to decimal
			checksum=`printf '%d\n' $checksum`
			# output for user
			printf "checksum is: $checksum\n"
			# insert separator
			checksum=$checksum"X"
			# read srk_fuse.bin
			srk_fuse=`cat $TMP_DIR/$SRK_HASH_TXT`
			# merge checksum + srk_fuse.bin
			echo $checksum$srk_fuse > $TMP_DIR/$SRK_HASH_TXT
			cp $TMP_DIR/$SRK_HASH_TXT $SRK_HASH_TXT
			printf "$SRK_HASH_TXT is ready!\n"
		else
			printf "\n%s characters != 64!, Aborting....\n\n" "$SRK_FUSE_BIN"
			exit 1
		fi
	else
		printf "\n%s length is not 32! Aborting....\n\n" "$SRK_FUSE_BIN"
		rm -r $TMP_DIR
		exit 1
	fi

	rm -r $TMP_DIR
	exit 0
}


# main function
handleParameters "$@"
setup_variables
check_serial

if [ "$?" == "0" ]; then
	create_serial
else
	printf "Serial and passphrase already exist\n"
fi

check_Certificates
if [ "$?" == "0" ]; then
	create_Certificates
fi

createSRK
createSRKHash

