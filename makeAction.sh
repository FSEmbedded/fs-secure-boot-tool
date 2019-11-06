#!/bin/bash

# handle script parameters

OPTS=`getopt -n 'generate'  -o: --long pad-to:,output:,loadaddr:,cpu:,action:,serial-interface:,auto-mode:,burn-fuses:,settings:,image-path:,key-length:,master-key:,jtag-resp-key:,cst-dir: -- "$@"`

eval set -- "$OPTS"

while true
do
    case "$1" in
	--pad-to )
	    PAD_SIZE="$2"
	    shift 2
	    ;;
	--output )
	    OUTPUT_NAME="$2"
	    shift 2
	    ;;
	--loadaddr )
	    LOAD_ADDR="$2"
	    shift 2
	    ;;
	--cpu )
	    CPU_ARCH="$2"
	    shift 2
	    ;;
	--action )
	    ACTION="$2"
	    shift 2
	    ;;
	--serial-interface )
	    SERIAL_DEVICE="$2"
	    shift 2
	    ;;
	--auto-mode )
	    mode="$2"
	    shift 2
	    ;;
	--burn-fuses )
	    burn_fuses="$2"
	    shift 2
	    ;;
	--settings )
	    settings="$2"
	    shift 2
	    ;;
	--image-path )
	    image_path="$2"
	    shift 2
	    ;;
	--key-length )
	    KEY_LENGTH="$2"
	    shift 2
	    ;;
	--master-key )
	    MASTER_KEY="$2"
	    shift 2
	    ;;
	--jtag-resp-key )
	    jtag_resp_key="$2"
	    shift 2
	    ;;
	--cst-dir )
	    cst_dir="$2"
	    shift 2
	    ;;
	* ) break
	    ;;
    esac
done

# evaluate "mode" parameter and set variables according to it

case "$mode" in
    0 )
	mode=true
	SERIAL_DEVICE="$SERIAL_DEVICE"  # keep entered serial device
	;;
    1 )
	mode=false
	SERIAL_DEVICE=nop               # no operation
	;;
esac

# evaluate "burn_fuses" parameter and set variables according to it

case "$burn_fuses" in
    0 )
	burn_fuses=true
	burn_fuses="$burn_fuses"  # keep entered serial device
	;;
    1 )
	burn_fuses=false
	burn_fuses=nop               # no operation
	;;
esac

# evaluate "CPU_ARCH" parameter and set variable according to it

case "$CPU_ARCH" in
    1 )
	CPU_ARCH=sdq
	;;
    2 )
	CPU_ARCH=sx
	;;
    3 )
	CPU_ARCH=ul
	;;
    4 )
	CPU_ARCH=ull
	;;
    5 )
	CPU_ARCH=vyb
	;;
esac

# set "ENGINE" parameter
case "$CPU_ARCH" in
	ull )
	ENGINE=SW
	;;
	* )
	ENGINE=ANY
	;;
esac

# evaluate "ACTION" parameter and set variable according to it

case "$ACTION" in
    c )
	ACTION=create
	;;
    j )
        ACTION=jtag
        ;;
    s )
	ACTION=sign
	;;
    e )
	ACTION=encrypt
	;;
esac

# when there is no "PAD_SIZE" parameter, set a defalut value
# (depending on the cpu)

if [ -z "$PAD_SIZE" ]; then
    case "$CPU_ARCH" in
	SDQ )
	    PAD_SIZE=80000
	    ;;
	SX )
	    PAD_SIZE=80000
	    ;;
	UL )
	    PAD_SIZE=80000
	    ;;
	ULL )
	    PAD_SIZE=80000
	    ;;
	VYB )
	    PAD_SIZE=60000
	    ;;
    esac
fi

# parse master key value
if [ "$MASTER_KEY" == "o" ] || [ "$MASTER_KEY" == "otpmk" ]; then
    MASTER_KEY="otpmk"
fi

# setup paths
if [ "$cst_dir" != "" ] ; then
    host_version=`uname -m | grep "64"`
    if [ -z $host_version ] ; then
        cst_sign_binary=`find ${cst_dir} -type f -iname "cst" | tail -n 1`
        cst_enc_binary="${cst_sign_binary}_encrypt"
        srktool_binary=`find ${cst_dir} -type f -iname "srktool" | tail -n 1`
    else
        cst_sign_binary=`find ${cst_dir} -type f -iname "cst" | head -n 1`
        cst_enc_binary="${cst_sign_binary}_encrypt"
        srktool_binary=`find ${cst_dir} -type f -iname "srktool" | tail -n 2 | head -n 1`
    fi
    if [ -z $cst_sign_binary ] || [ -z $srktool_binary ] ; then
        exit 1
    fi
else
    exit 1
fi

# call subscripts (depending on "ACTION")
if [ "$ACTION" == "create" ]; then
    # call script for creating the certificates
    ./createCertificates.sh c "$cst_dir" "$srktool_binary"
    exit 0
fi

if [ "$ACTION" == "jtag" ]; then
    ./jtag.sh "$jtag_resp_key"
fi

if [ "$ACTION" == "sign" ]; then
    # call script for signing an image
    ./signImage.sh "$CPU_ARCH" "$OUTPUT_NAME" "$LOAD_ADDR" "$image_path" \
                   "$cst_sign_binary"
    if [ "$?" == "0" ]; then
	exit 0
    else
	exit 1
    fi
elif [ "$ACTION" == "encrypt" ]; then
    ./encryptImage.sh "$CPU_ARCH" "$OUTPUT_NAME" "$LOAD_ADDR" "$image_path" \
                      "$KEY_LENGTH" "$MASTER_KEY" "$ENGINE" "$cst_dir" "$cst_enc_binary"
    exit $?
fi
