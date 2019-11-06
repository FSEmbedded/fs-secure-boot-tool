#!/bin/bash

# handle script parameters

OPTS=`getopt -n 'generate'  -o: --long pad-to:,output:,loadaddr:,cpu:,action:,serial-interface:,auto-mode:,burn-fuses:,settings:,image-path:,key-length:,master-key:,jtag-resp-key:,cst-dir: -- "$@"`

eval set -- "$OPTS"

while true
do
    case "$1" in
	--pad-to )
	    pad_size="$2"
	    shift 2
	    ;;
	--output )
	    output_name="$2"
	    shift 2
	    ;;
	--loadaddr )
	    load_addr="$2"
	    shift 2
	    ;;
	--cpu )
	    cpu_arch="$2"
	    shift 2
	    ;;
	--action )
	    action="$2"
	    shift 2
	    ;;
	--serial-interface )
	    serial_device="$2"
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
	    key_length="$2"
	    shift 2
	    ;;
	--master-key )
	    master_key="$2"
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
	serial_device="$serial_device"  # keep entered serial device
	;;
    1 )
	mode=false
	serial_device=nop               # no operation
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

# evaluate "cpu_arch" parameter and set variable according to it

case "$cpu_arch" in
    1 )
	cpu_arch=sdq
	;;
    2 )
	cpu_arch=sx
	;;
    3 )
	cpu_arch=ul
	;;
    4 )
	cpu_arch=ull
	;;
    5 )
	cpu_arch=vyb
	;;
esac

# set "engine" parameter
case "$cpu_arch" in
	ull )
	engine=SW
	;;
	* )
	engine=ANY
	;;
esac

# evaluate "action" parameter and set variable according to it

case "$action" in
    c )
	action=create
	;;
    j )
        action=jtag
        ;;
    s )
	action=sign
	;;
    e )
	action=encrypt
	;;
esac

# when there is no "pad_size" parameter, set a defalut value
# (depending on the cpu)

if [ -z "$pad_size" ]; then
    case "$cpu_arch" in
	SDQ )
	    pad_size=80000
	    ;;
	SX )
	    pad_size=80000
	    ;;
	UL )
	    pad_size=80000
	    ;;
	ULL )
	    pad_size=80000
	    ;;
	VYB )
	    pad_size=60000
	    ;;
    esac
fi

# parse master key value
if [ "$master_key" == "o" ] || [ "$master_key" == "otpmk" ]; then
    master_key="otpmk"
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

# call subscripts (depending on "action")
if [ "$action" == "create" ]; then
    # call script for creating the certificates
    ./createCertificates.sh c "$cst_dir" "$srktool_binary"
    exit 0
fi

if [ "$action" == "jtag" ]; then
    ./jtag.sh "$jtag_resp_key"
fi

if [ "$action" == "sign" ]; then
    # call script for signing an image
    ./signImage.sh "$cpu_arch" "$output_name" "$load_addr" "$image_path" \
                   "$engine" "$cst_sign_binary"
    if [ "$?" == "0" ]; then
	exit 0
    else
	exit 1
    fi
elif [ "$action" == "encrypt" ]; then
    ./encryptImage.sh "$cpu_arch" "$output_name" "$load_addr" "$image_path" \
                      "$key_length" "$master_key" "$engine" "$cst_dir" "$cst_enc_binary"
    exit $?
fi
