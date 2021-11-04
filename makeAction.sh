#!/bin/bash

# handle script parameters

OPTS=`getopt -n 'generate'  -o: --long output:,loadaddr:,cpu:,action:\
,serial-interface:,auto-mode:,burn-fuses:,settings:,image-path:\
,key-length:,master-key:,jtag-resp-key:,cst-dir: -- "$@"`

eval set -- "$OPTS"

while true
do
    case "$1" in
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
	* )
	printf "\nWrong action parameter $action! Aborting....\n\n"
	exit 1
esac

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

# check parameters for script jtag.sh
if [ "$action" == "jtag" ]; then
	chrlen=${#jtag_resp_key}
	if [ $chrlen != 14 ]; then
		printf "\nJTAG key length $chrlen != 14! Aborting....\n\n"
	fi
	if ! [[ $jtag_resp_key =~ [0-9A-Fa-f]{$chrlen} ]]; then
		printf "\nJTAG resp key $jtag_resp_key is not a hex number! "
		printf "Aborting....\n\n"
		exit 1
	fi
fi

# check parameters for script encryptImage.sh
if [ "$action" == "encrypt" ]; then
	if [ $key_length != 128 ] && [ $key_length != 192 ] && \
		[ $key_length != 256 ]; then
		printf "\nWrong key length! Aborting....\n\n"
		exit 1
	fi

	# parse master key value
	if [ "$master_key" == "o" ] || [ "$master_key" == "otpmk" ]; then
		master_key="otpmk"
	else
		printf "\nMaster key '$master_key' not supported! Aborting....\n\n"
		exit 1
	fi
fi

# check parameters for script signImage.sh / encryptImage.sh
if [ "$action" == "sign" ] || [ "$action" == "encrypt" ]; then
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
		* )
		printf "\nUnknown cpu_arch! Aborting....\n\n"
		exit 1
		;;
	esac

	# if output_name is not set, it generates automatically one

	# if load_addr is set, check if it´s a hex number
	if [ -n "$load_addr" ]; then
		chrlen=${#load_addr}
		if ! [[ $load_addr =~ [0-9A-Fa-f]{$chrlen} ]]; then
			printf "\nload_addr $load_addr is not a hex number! "
			printf "Aborting....\n\n"
			exit 1
		fi
	fi

	# check if image exists
	if [ ! -f "$image_path" ]; then
		printf "\nFile: $image_path does not exist! Aborting....\n\n"
	exit 1
	fi

	# set "engine" parameter
	case "$cpu_arch" in
		ull )
		engine=SW
		;;
		* )
		engine=ANY
		;;
	esac
fi

# check parameter for script createCertificates.sh / signImage.sh /
# encryptImage.sh
if [ "$action" == "create" ] || [ "$action" == "sign" ] || \
	[ "$action" == "encrypt" ]; then
    # setup paths
	if [ -d "$cst_dir" ] ; then
		host_version=`uname -m | grep "64"`
		if [ ! -z $host_version ] ; then
			srktool_binary=`find ${cst_dir} -type f -iname "srktool" |\
			grep linux | tail -n 1`
			read -a version <<< $(${CST_DIR}/linux64/bin/srktool -v)
			version=${version[5]}
			cst_sign_binary=`find ${cst_dir} -type f -iname "cst" |\
			grep linux | tail -n 1`
		else
			srktool_binary=`find ${cst_dir} -type f -iname "srktool" |\
			grep linux | tail -n 2 | head -n 1`
			read -a version <<< $(${CST_DIR}/linux64/bin/srktool -v)
			version=${version[5]}
			cst_sign_binary=`find ${cst_dir} -type f -iname "cst" |\
			grep linux | head -n 1`
		fi
		if [ -z $cst_sign_binary ] || [ -z $srktool_binary ]; then
			printf "\n Unable setup variables cst_sign_binary "
			printf "and srktool_binary! Aborting....\n\n"
			exit 1
		fi
		if [ ${version:0:1} -eq 3 ]; then
			if [ ${version:2:1} -ge 3 ]; then
				cst_enc_binary="${cst_sign_binary}"
			else
				echo ${version:2:1}
				cst_enc_binary="${cst_sign_binary}_encrypt"
			fi
		elif [ ${version:0:1} -lt 3 ]; then
			cst_enc_binary="${cst_sign_binary}"
		else
			cst_enc_binary="${cst_sign_binary}_encrypt"
		fi
		if [ -z $cst_enc_binary ]; then
			printf "\n Unable setup variable "
			printf "cst_enc_binary! Aborting....\n\n"
			exit 1
		fi
	else
		printf "\n CST directory doesn´t exist! Aborting....\n\n"
		exit 1
	fi
fi


# call subscripts (depending on "action")
if [ "$action" == "create" ]; then
	# call script for creating the certificates
	./createCertificates.sh "$cst_dir" "$srktool_binary"
elif [ "$action" == "jtag" ]; then
	# call script for creating a JTAG response key
	./jtag.sh "$jtag_resp_key"
elif [ "$action" == "sign" ]; then
	# call script for signing an image
	./signImage.sh "$cpu_arch" "$output_name" "$load_addr" "$image_path" \
			"$engine" "$cst_sign_binary"
elif [ "$action" == "encrypt" ]; then
	# call script for encrypting an image
	./encryptImage.sh "$cpu_arch" "$output_name" "$load_addr" "$image_path" \
			"$key_length" "$master_key" "$engine" "$cst_dir" "$cst_enc_binary"
fi
exit $?
