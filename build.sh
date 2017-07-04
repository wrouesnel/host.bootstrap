#!/bin/bash
# Simple build script for a simple system

if [ $EUID != 0 ]; then
    exec sudo "$0" "$@"
fi

SUITE=zesty
root=root

function join { local IFS="$1"; shift; echo "$*"; }

# make_dir makes a directory to the given path in the root
function make_dir() {
    mkdir $root/$1
}

function bootstrap_make_dir() {
    make_dir "$1"
    echo "rmdir -v /sysroot/$1 || /bin/true" >> bootstrap_cleanup
}

# copy_file copies file to the given path in the root
function copy_file() {
    cp -f "$1" "$root/$2"
}

# bootstrap_copy copies a file and writes a removal entry for after
# the bootstrap script has run (i.e. it is deleted from the image copied out
# of the bootstrap initrd
function bootstrap_copy_file() {
    copy_file "$1" "$2"
    echo "rm -v -f /sysroot/$2" >> bootstrap_cleanup
}

# mk_symlink builds a symlink pointed to arg1 at arg2 in the image.
function make_symlink() {
    ln -sf "$1" "$root/$2"
}

function bootstrap_make_symlink() {
    make_symlink "$1" "$2"
    echo "rm -v -f /sysroot/$2" >> bootstrap_cleanup
}

PACKAGES=(
    sudo \
    e2fsprogs \
    gdisk \
    coreutils \
    systemd \
    systemd-sysv \
    dbus \
    login \
    rsync \
    procps \
    mount \
    less \
    grep \
    sed \
    nano \
    util-linux \
    locales \
    iproute2 \
    kexec-tools \
    python \
    apt-transport-https \
    openssh-server \
    grub-pc \
    linux-image-generic
)

# Clean up the old root
[ -e "$root" ] && [ ! -z "$root" ] && rm -rf $root

# Empty the bootstrap_cleanup file
> bootstrap_cleanup

echo "Bootstrapping..."
http_proxy=$http_proxy https_proxy=$https_proxy debootstrap \
    --include $(join "," "${PACKAGES[@]}") \
    --components main,universe,multiverse \
    --variant=minbase $SUITE $root $mirror || exit 1

echo "Add modifications"
bootstrap_make_dir /etc/systemd/system/initrd.target.wants
make_dir /sysroot

make_dir /etc/systemd/system/systemd-networkd.service.d
copy_file systemd-networkd-dbus.conf /etc/systemd/system/systemd-networkd.service.d/systemd-networkd-dbus.conf

echo "Setting generic DHCP networking"
copy_file all.network /etc/systemd/network/all.network
make_symlink /lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
make_symlink /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
make_symlink /lib/systemd/resolv.conf /etc/resolv.conf

#echo "Getty autologin"
#mkdir $root/etc/systemd/system/getty@tty1.service.d
#cp autologin-tty.conf $root/etc/systemd/system/getty@tty1.service.d/autologin-tty.conf

#mkdir $root/etc/systemd/system/getty@ttyS0.service.d
#cp autologin-serial.conf $root/etc/systemd/system/getty@ttyS0.service.d/autologin-serial.conf

#mkdir $root/etc/systemd/system/getty@.service.d
#cp getty-noclear.conf $root/etc/systemd/system/getty@.service.d/getty-noclear.conf

echo "Set hostname"
echo "bootstrap" > $root/etc/hostname

echo "Bootstrap /etc/hosts"
copy_file hosts /etc/hosts

echo "Set default target..."
bootstrap_make_symlink /lib/systemd/system/initrd.target /etc/systemd/system/default.target

echo "Activate systemd in initrd"
bootstrap_make_symlink /lib/systemd/systemd /init

#echo "Machine ID set unit"
#bootstrap_make_dir /etc/systemd/system/sysinit.target.wants
#bootstrap_copy_file generate-machine-id.service /etc/systemd/system/generate-machine-id.service
#bootstrap_make_symlink /etc/systemd/system/generate-machine-id.service /etc/systemd/system/sysinit.target.wants/generate-machine-id.service

echo "Provisioning script"
bootstrap_copy_file bootstrap /bootstrap
bootstrap_copy_file bootstrap.service /etc/systemd/system/bootstrap.service
bootstrap_make_dir /etc/systemd/system/initrd-root-device.target.wants
bootstrap_make_symlink /etc/systemd/system/bootstrap.service /etc/systemd/system/initrd-root-device.target.wants/bootstrap.service

copy_file ssh-host-keys.service /etc/systemd/system/ssh-host-keys.service
make_dir /etc/systemd/system/ssh.service.wants
make_symlink /etc/systemd/system/ssh-host-keys.service /etc/systemd/system/ssh.service.wants/ssh-host-keys.service

echo "Copying cleanup directives"
# Duplicate the copy so we actually incorporate the copy.
tac bootstrap_cleanup > bootstrap_cleanup.real
bootstrap_copy_file bootstrap_cleanup.real /bootstrap_cleanup
tac bootstrap_cleanup > bootstrap_cleanup.real
bootstrap_copy_file bootstrap_cleanup.real /bootstrap_cleanup

# Remove un-needed things
cp $root/boot/vmlinuz-* vmlinuz
# Important - delete the SSH host keys so the bootstrapper sets them up.
rm -rf $root/var/cache/apt/archives/*
rm -f $root/etc/ssh/*_key rm -f $root/etc/ssh/*_key.pub

# Notify systemd it'll be initrd mode
mv $root/etc/os-release $root/etc/initrd-release

# Clear out /etc/machine-id (bootstrap will generate one).
> $root/etc/machine-id

echo "Building initrd..."

cd root || exit 1

# Command which builds the initramfs
find . | cpio -H newc -o | gzip -c > ../initrd || exit 1

cd ..

chown $SUDO_UID:$SUDO_GID vmlinuz initrd

echo "Build Finished"

echo "Starting Virtual Machine..."
sudo -u $(id -n -u $SUDO_UID) -g $(id -n -g $SUDO_GID) ./build-2.sh
