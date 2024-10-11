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

download_latest_image() {
    OS_IMAGE=$(mktemp /tmp/raspios_rpi.XXXXXX)
    trap "echo '[*] Deleting image'; rm -f $OS_IMAGE" 0 2 3 15

    echo "[*] Downloading OS image from $RASPIOS_LATEST_URL"
    wget $RASPIOS_LATEST_URL -q --show-progress -O $OS_IMAGE
    echo $(wget $RASPIOS_CHKSUM_URL -O- -o /dev/null | cut -f1 -d' ') $OS_IMAGE | sha256sum --check --status

    exit_status=$?
    if [ $exit_status -eq 1 ];
    then
        echo "[-] Image checksum validation failed"
         exit 1
    else
        echo "[+] Image checksum verified"
    fi
    echo "$OS_IMAGE"
}

# Real script path
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"

usage() {
    cat << EOF
Usage: $0 <ARGS> <OPTARGS>

<ARGS>:
    -i, --image{"latest",PATH}: Download latest or RasPiOS image file path
    -k, --key{STRING|PATH}:     SSH public key or 'authorized_keys' file path

<OPTARGS>
    -o, --output{PATH}: Output image path. Original is overwritten if not set.
EOF
    exit 1
}

while test $# != 0
do
    case "$1" in
    -i|--image)
        INPUT_IMAGE="$2"; shift;;
    -k|--key)
        SSH_KEY="$2"; shift;;
    -o|--output)
        OUTPUT_IMAGE="$2"; shift;;
    --) shift; break;;
    *)  usage;;
    esac
    shift
done

case "" in
    "$INPUT_IMAGE"|"$SSH_KEY")
        usage ;;
esac

if [ "$INPUT_IMAGE" == "latest" ]; then
    INPUT_IMAGE=$(download_latest_image)
fi
check_file_or_die "$INPUT_IMAGE"

# Copy image if --output is set. I need to do this because SDM's --customize
# flag overwrites the original image.
if [ -v "OUTPUT_IMAGE" ]; then
    echo "[*] Creating new image '$OUTPUT_IMAGE'"
    pv $INPUT_IMAGE | dd bs=16M iflag=fullblock of=$OUTPUT_IMAGE
    INPUT_IMAGE=$OUTPUT_IMAGE # We don't need the original INPUT_IMAGE anymore
fi

if [ -f "$SSH_KEY" ]; then
    echo "[+] Using $SSH_KEY file"
    SSH_PLUGIN_ARG="keysfile=$SSH_KEY"
else
    echo "[+] Using public key '$SSH_KEY'"
    SSH_PLUGIN_ARG="pubkey='$SSH_KEY'"
fi

function cleanup (){
    echo '[*] Cleaning up'
}
trap cleanup EXIT INT QUIT TERM

docker_repo="deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable"
docker_gpg_key=https://download.docker.com/linux/debian/gpg

sdm \
    --customize \
    --extend \
    --xmb 4096 \
    --batch \
    --plugin-debug \
    --plugin @$DIR/config/plugins.txt \
    --plugin apt-addrepo:"repo=$docker_repo|gpgkey=$docker_gpg_key|gpgkeyname=docker" \
    --plugin $DIR/plugins/ssh:"user=neo|$SSH_PLUGIN_ARG" \
    $INPUT_IMAGE
