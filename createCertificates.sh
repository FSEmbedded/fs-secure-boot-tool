#!/bin/bash


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
    CST_DIR=$2
    SRKTOOL_BINARY=$3
}


################################################################################
# function: setup_variables
#
# parameters:
#
# return: -
#
# description:
# Setup some environment variables
#
################################################################################

function setup_variables()
{
    # get path to crts folder
    CRTS_DIR=`find ${CST_DIR} -type d -iname "crts"`
    # get path to keys folder
    KEYS_DIR=`find ${CST_DIR} -type d -iname "keys"`
}

################################################################################
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
################################################################################

function check_serial()
{
    if [ -f $KEYS_DIR/serial ] && [ -f $KEYS_DIR/key_pass.txt ]; then
	return 1
    else
	return 0
    fi
}


################################################################################
# function: create_serial
#
# parameters:

# return:
#
# description:
# Creates the serial and key_pass.txt containing the serial number and the
# keys passphrease.
# Important note: openssl expect the given filenames!
################################################################################

function create_serial()
{
    printf "\nPlease enter a serial number (8 digits!):"
    local serial
    read serial
    echo $serial > serial
    mv serial $KEYS_DIR/

    printf "Please enter a passphrase (no blanks!):"
    local passPhrase
    read passPhrase
    echo $passPhrase > key_pass.txt
    echo $passPhrase >> key_pass.txt
    mv key_pass.txt $KEYS_DIR/
}


################################################################################
# function: check_Certificates()
#
# parameters: -
#
# return: 0: Certificates don't exist
#         1: Certificates exist
# description:
# Checks if the certificates already exist
################################################################################

function check_Certificates()
{
    if [ `ls -l $CRTS_DIR/SRK*.pem 2>/dev/null | wc -l` -gt 0 ]; then
	printf "Certificates already exist!\b\n"
	return 1
    else
	return 0
    fi
}


################################################################################
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
################################################################################

function create_Certificates()
{
    # we have to switch inside the $KEYS_DIR to create certificates because
    # it copy the certificates to necessary crts/keys folder from its relativ
    # path.
    home=$PWD
    cd $KEYS_DIR
    if [ "$1" == "d" ]; then                    # default settings
	./hab4_pki_tree.sh 2>/dev/null          # generate no output on console
    elif [ "$1" == "c" ]; then                  # create own settings
	./hab4_pki_tree.sh -m  2>/dev/null      # generate no output on console
    fi
    if [ $? == "1" ]; then
	printf "An Error occured! Aborting....\b\n"
	exit 1
    else
	printf "Certificate(s) sucessfully created\b\n"
    fi

    cd $home
}

################################################################################
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
################################################################################

function createSRK()
{
    pattern=SRK1*.pem

    file=`basename ${CRTS_DIR}/$pattern`
    count=`ls -d ${CRTS_DIR}/SRK*.pem | wc -l`

    case "$file" in
        *1024*)
            kl=1024
            ;;
        *2048*)
            kl=2048
            ;;
        *3072*)
            kl=3072
            ;;
        *4096*)
            kl=4096
            ;;
        *)
            echo "error: keylength not matched!"
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
            echo "error: format not known!"
            exit 1
    esac

    if [ "$count" = "1" ]; then
	$SRKTOOL_BINARY -h 4 -t $CRTS_DIR/SRK_Table.bin -e $CRTS_DIR/SRK_fuse.bin -d sha256 -c $CRTS_DIR/SRK1_sha256_${kl}_65537_v3_${flag}_crt.pem -f 1

    elif [ "$count" = "2" ]; then

	$SRKTOOL_BINARY -h 4 -t $CRTS_DIR/SRK_Table.bin -e $CRTS_DIR/SRK_fuse.bin -d sha256 -c $CRTS_DIR/SRK1_sha256_${kl}_65537_v3_${flag}_crt.pem,$CRTS_DIR/SRK2_sha256_${kl}_65537_v3_${flag}_crt.pem -f 1

    elif [ "$count" = "3" ]; then

	$SRKTOOL_BINARY -h 4 -t $CRTS_DIR/SRK_Table.bin -e $CRTS_DIR/SRK_fuse.bin -d sha256 -c $CRTS_DIR/SRK1_sha256_${kl}_65537_v3_${flag}_crt.pem,$CRTS_DIR/SRK2_sha256_${kl}_65537_v3_${flag}_crt.pem,$CRTS_DIR/SRK3_sha256_${kl}_65537_v3_${flag}_crt.pem -f 1

    elif [ "$count" = "4" ]; then

	$SRKTOOL_BINARY -h 4 -t $CRTS_DIR/SRK_Table.bin -e $CRTS_DIR/SRK_fuse.bin -d sha256 -c $CRTS_DIR/SRK1_sha256_${kl}_65537_v3_${flag}_crt.pem,$CRTS_DIR/SRK2_sha256_${kl}_65537_v3_${flag}_crt.pem,$CRTS_DIR/SRK3_sha256_${kl}_65537_v3_${flag}_crt.pem,$CRTS_DIR/SRK4_sha256_${kl}_65537_v3_${flag}_crt.pem  -f 1

    fi

    #modify boot_raw (CSF)
    sed -e "s/###BIT###/$kl/" boot_raw > boot_raw_edited

    rm boot_raw
}


################################################################################
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
################################################################################

function createSRKHash()
{
    if [ -z "$1" ] ; then
	echo "File not found!"
	exit 0
    else
	SRK="$1"
    fi
    srk_file="srkhash.txt"
    SIZE_SRK_FUSE=`stat -c %s "$SRK"`
    if [ "$SIZE_SRK_FUSE"  == "32" ]; then
	SIGNS=`hexdump -v -e '/1 "%02X"' "$SRK" | wc -c`
	if [ "$SIGNS" == "64" ]; then
	    hexdump -v -e '/1 "%02X"' "$SRK" > $srk_file
	    HASH=`cat $srk_file`
	    erg_old=0x00
	    erg=0
	    i=1

	    #create checksum
	    while [ $i -le 16 ]
	    do
		zahl1=`echo $HASH | cut -b 1-2`
		zahl2=`echo $HASH | cut -b 3-4`
		zahl1="0x"$zahl1""
		zahl2="0x"$zahl2""
		zerg=`echo $(($zahl1 + $zahl2))`
		nerg=$((zerg+erg_old))
		erg_old=nerg
		HASH=`echo ${HASH:4}`
		i=$[i + 1]
	    done
	    #decimal
	    var=`printf '%d\n' $nerg`
	    #checksum
	    echo "checksum is: "$var
	    var2=$var"X"
	    HASH=`cat $srk_file`
	    echo $var2$HASH > $srk_file
	    echo $srk_file" is ready!"
	else
	    echo "SRK Table not found!"
	    exit 1
	fi
    elif [ -z "$SIZE_SRK_FUSE" ]; then
	exit 1
    else
	echo "SRK Table not found!"
	exit 1
    fi

}


# main function
handleParameters "$@"
setup_variables
check_serial
if [ "$?" == "0" ]; then
    create_serial
else
    printf "Serial and passphrase already exist\b\n"
fi
check_Certificates
if [ "$?" == "0" ]; then
    create_Certificates $1
fi

createSRK
createSRKHash "$CRTS_DIR/SRK_fuse.bin"

exit 0
