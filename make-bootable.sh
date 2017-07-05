#!/bin/bash
# Writes the vmlinuz and initrd alongside a bootloader to a USB key.

if [ $EUID != 0 ]; then
    exec sudo "$0" "$@"
fi

. settings.sh

rootfs=${usb_key_rootfs:-ext4}

function fatal() {
    exit_code=$1
    shift
    echo "$@"
    exit $1
}

if [ -z "$1" ] ; then 
    echo "Need a device to setup."
    exit 1
fi

if [ ! -e "$1" ] ; then
    echo "Device does not exist: $1"
    exit 1
fi

target_device="$1"

echo "Partitioning..."
sgdisk -n 1:0:+1M -n 2:0:0 -t 1:ef02 -t 2:8300 -c 1:"grub" ${target_device} || \
    fatal 1 "Partitioning failed."

echo "Refreshing partition tables..."
partprobe ${target_device}

target_partition=${target_device}p2

echo "Making filesystem..."
mkfs.$rootfs "${target_partition}" || fatal 1 "Failed to make filesystem."

rootuuid=$(blkid -s UUID -o value "${target_partition}")

echo "Mounting filesystem..."
mkdir -p $mnt
mount "${target_partition}" $mnt

echo "Making directory..."
mkdir -p $mnt/boot/grub

echo "Doing initial grub-install..."
grub-install --grub-mkdevicemap=$tmp/device.map \
    --root-directory=$mnt \
    --boot-directory=$mnt/boot \
    --target=i386-pc || fatal 1 "Failed to do grub-install"

echo "Template grub early conf..."
cat << EOF > $tmp/earlygrub.cfg
# Basic boot modules
insmod part_gpt
insmod $rootfs
insmod search
insmod search_fs_uuid
insmod biosdisk
# Quality of life modules
insmod echo
insmod cat
insmod terminal
insmod serial
# Serial support as early as possible is absolutely vital
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input --append serial
terminal_output --append serial
search --fs-uuid $rootuuid --set=root
set prefix=(\$root)/boot/grub
EOF

echo "Template grub conf..."
cat << EOF > $tmp/grub.cfg
# This is a bootstrap grub configuration file. Provisioned images should build
# a similar, specific file, on first boot on new hardware.
set default="0"
set timeout=3
insmod part_gpt
insmod $rootfs
search --fs-uuid $rootuuid root
menuentry 'Bootstrap grub.cfg' {
	insmod gzio
	linux	/boot/vmlinuz ro root=UUID=$rootuuid console=tty0 console=ttyS0,115200n8
	initrd	/boot/initrd
}
EOF

echo "Building grub grub core.img file..."
grub-mkimage --prefix="" \
    --config=$tmp/earlygrub.cfg \
    --compression=auto \
    -o $tmp/core.img \
    -O i386-pc || fatal 1 "Failed to build grub core.img file."
    $(cat $tmp/earlygrub.cfg | grep insmod | cut -d' ' -f2 | paste -d, -s)
    
echo "Installing grub core.img file..."
grub-bios-setup --core-image=core.img \
    --boot-image=boot.img \
    --directory=$mnt/boot/grub \
    --device-map=$tmp/device.map \
    ${target_device}

echo "Cleaning up..."
umount -f $mnt

