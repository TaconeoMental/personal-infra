#!/usr/bin/env bash

if [ $UID -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi


echo_die() {
    if (( $# == 0 )); then
        cat /dev/stdin
    else
        echo "$1"
    fi
    exit 1
}

check_file_or_die() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        echo_die "[-] $filepath is not a valid file"
    fi
}

usage() {
    echo_die << EOF
Usage: $0 <ARGS> <OPTARGS> <OUTPUT>

<ARGS>:
    -i, --image{PATH}:      SDM enhanced RaspiOS image
    -H, --hostname{STRING}: Set device hostname

<OPTARGS>
    -e, --encrypt:          Encrypt rootfs
    -k, --keys{PATH}:       SSH authorized keys file for use in the initramfs

<OUTPUT>
    -w, --write{PATH}:      Write image to file
    -d, --device{PATH}:     Burn image to device
EOF
}

ENCRYPT_ROOTFS=false
while test $# != 0
do
    case "$1" in
    -i|--image)
        INPUT_IMAGE="$2"; shift;;
    -H|--hostname)
        HOSTNAME="$2"; shift;;
    -w|--write)
        OUTPUT_IMAGE="$2"; shift;;
    -d|--device)
        OUTPUT_DEVICE="$2"; shift;;
    -e|--encrypt)
        ENCRYPT_ROOTFS=true;;
    -k|--keys)
        AUTH_KEYS_FILE="$2"; shift;;
    --) shift; break;;
    *)  usage;;
    esac
    shift
done

case "" in
    "$INPUT_IMAGE"|"$HOSTNAME")
        usage ;;
esac

check_file_or_die $INPUT_IMAGE

if [ -z "$OUTPUT_IMAGE" ] && [ -z "$OUTPUT_DEVICE" ]; then
    echo_die "[-] No output specified (--write, --device)"
fi

if [ -n "$OUTPUT_IMAGE" ] && [ -n "$OUTPUT_DEVICE" ]; then
    echo_die "[-] Must specify only one output (--write, --device)"
fi

if [ "$ENCRYPT_ROOTFS" == "false" ]; then
    [ -n "$AUTH_KEYS_FILE" ] \
        && echo_die "[-] --keys and --port can only be used with the --encrypt flag"
fi

ENCRYPT_ARGUMENT=""
if [ "$ENCRYPT_ROOTFS" == "true" ]; then
    [ -z "$AUTH_KEYS_FILE" ] && echo_die '[-] You must specify an SSH authorized keys file'
    check_file_or_die $AUTH_KEYS_FILE
    ENCRYPT_ARGUMENT="--plugin cryptroot:ssh"
    ENCRYPT_ARGUMENT="${ENCRYPT_ARGUMENT}|ihostname=$HOSTNAME-crypt"
    ENCRYPT_ARGUMENT="${ENCRYPT_ARGUMENT}|crypto=xchacha"
    ENCRYPT_ARGUMENT="${ENCRYPT_ARGUMENT}|authkeys=$AUTH_KEYS_FILE"
fi

BURN_ARGUMENT="--burn $OUTPUT_DEVICE"
if [ -n "$OUTPUT_IMAGE" ]; then
    BURN_ARGUMENT="--burnfile $OUTPUT_IMAGE"
fi

sdm \
    $BURN_ARGUMENT \
    --host $HOSTNAME \
    --expand-root \
    --regen-ssh-host-key \
    --ecolors 0 \
    --mcolors 0 \
    $ENCRYPT_ARGUMENT \
    $INPUT_IMAGE
