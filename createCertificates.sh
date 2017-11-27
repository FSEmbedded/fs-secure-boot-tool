#!/bin/bash



################################################################################
# function: check_serial
#
# parameters:
#
# return: 0: serial and passphrase don't exit
#         1: serial and passphrase exist
#
# description:
# Checks if there is a file serial or key_pass.txt
#
################################################################################

function check_serial()
{
    if [ -f ./cst-2.3.2/keys/serial -o -f ./cst-2.3.2/keys/serial ]; then
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
    mv serial ./cst-2.3.2/keys/

    printf "Please enter a passphrase (no blanks!):"
    local passPhrase
    read passPhrase
    echo $passPhrase > key_pass.txt
    echo $passPhrase >> key_pass.txt
    mv key_pass.txt ./cst-2.3.2/keys/
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
    if [ `ls -l ./cst-2.3.2/crts/SRK*.pem 2>/dev/null | wc -l` -gt 0 ]; then
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
    cd ./cst-2.3.2/keys/
    cp ../../boot_raw .
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

    cd ../../
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
    path=./cst-2.3.2/crts/

    file=`basename $path$pattern`
    count=`ls -d ${path}SRK*.pem | wc -l`

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

    if [ "$count" = "1" ]; then
	./cst-2.3.2/linux64/srktool -h 4 -t ./cst-2.3.2/crts/SRK_Table.bin -e ./cst-2.3.2/crts/SRK_fuse.bin -d sha256 -c ./cst-2.3.2/crts/SRK1_sha256_${kl}_65537_v3_ca_crt.pem -f 1

    elif [ "$count" = "2" ]; then

	./cst-2.3.2/linux64/srktool -h 4 -t ./cst-2.3.2/crts/SRK_Table.bin -e ./cst-2.3.2/crts/SRK_fuse.bin -d sha256 -c ./cst-2.3.2/crts/SRK1_sha256_${kl}_65537_v3_ca_crt.pem,./cst-2.3.2/crts/SRK2_sha256_${kl}_65537_v3_ca_crt.pem -f 1

    elif [ "$count" = "3" ]; then

	./cst-2.3.2/linux64/srktool -h 4 -t ./cst-2.3.2/crts/SRK_Table.bin -e ./cst-2.3.2/crts/SRK_fuse.bin -d sha256 -c ./cst-2.3.2/crts/SRK1_sha256_${kl}_65537_v3_ca_crt.pem,./cst-2.3.2/crts/SRK2_sha256_${kl}_65537_v3_ca_crt.pem,./cst-2.3.2/crts/SRK3_sha256_${kl}_65537_v3_ca_crt.pem -f 1

    elif [ "$count" = "4" ]; then

	./cst-2.3.2/linux64/srktool -h 4 -t ./cst-2.3.2/crts/SRK_Table.bin -e ./cst-2.3.2/crts/SRK_fuse.bin -d sha256 -c ./cst-2.3.2/crts/SRK1_sha256_${kl}_65537_v3_ca_crt.pem,./cst-2.3.2/crts/SRK2_sha256_${kl}_65537_v3_ca_crt.pem,./cst-2.3.2/crts/SRK3_sha256_${kl}_65537_v3_ca_crt.pem,./cst-2.3.2/crts/SRK4_sha256_${kl}_65537_v3_ca_crt.pem  -f 1

    fi

#modify boot_raw (CSF)
    sed -e "s/###BIT###/$kl/" ./boot_raw > boot_raw_edited
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
createSRKHash "${PWD}/cst-2.3.2/crts/SRK_fuse.bin"

exit 0
