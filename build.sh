#!/bin/bash
# Simple build script for a simple system

if [ $EUID != 0 ]; then
    exec sudo "$0" "$@"
fi

. settings.sh

function join { local IFS="$1"; shift; echo "$*"; }

# make_dir makes a directory to the given path in the root
function make_dir() {
    mkdir $root/$1
}

function bootstrap_make_dir() {
    make_dir "$1"
    echo "rmdir -v /sysroot/$1 || /bin/true" >> $tmp/bootstrap_cleanup
}

# move_file moves a file around within the context of the root
function move_file() {
    mv -f "$root/$1" "$root/$2"
}

# copy_file copies file to the given path in the root
function copy_file() {
    cp -f "$src/$1" "$root/$2"
}

function wipe_file() {
    > "$root/$1"
}

# bootstrap_copy copies a file and writes a removal entry for after
# the bootstrap script has run (i.e. it is deleted from the image copied out
# of the bootstrap initrd
function bootstrap_copy_file() {
    copy_file "$1" "$2"
    echo "rm -v -f /sysroot/$2" >> $tmp/bootstrap_cleanup
}

# mk_symlink builds a symlink pointed to arg1 at arg2 in the image.
function make_symlink() {
    ln -sf "$1" "$root/$2"
}

function bootstrap_make_symlink() {
    make_symlink "$1" "$2"
    echo "rm -v -f /sysroot/$2" >> $tmp/bootstrap_cleanup
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
# Clean up the old boot
[ -e "$boot" ] && [ ! -z "$boot" ] && rm -rf $boot && mkdir -p "$boot"
# Clean up old tmp
[ -e "$tmp" ] && [ ! -z "$tmp" ] && rm -rf $tmp && mkdir -p "$tmp"

# Empty the bootstrap_cleanup file
> $tmp/bootstrap_cleanup

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
tac $tmp/bootstrap_cleanup > $tmp/bootstrap_cleanup.real
bootstrap_copy_file ../$tmp/bootstrap_cleanup.real /bootstrap_cleanup
tac $tmp/bootstrap_cleanup > $tmp/bootstrap_cleanup.real
bootstrap_copy_file ../$tmp/bootstrap_cleanup.real /bootstrap_cleanup

# Remove un-needed things
# Important - delete the SSH host keys so the bootstrapper sets them up.
rm -rf $root/var/cache/apt/archives/*
rm -f $root/etc/ssh/*_key rm -f $root/etc/ssh/*_key.pub

# Notify systemd it'll be initrd mode
move_file /etc/os-release /etc/initrd-release

# Clear out /etc/machine-id (bootstrap will generate one).
wipe_file /etc/machine-id

echo "Extracting kernel..."
# Extract the kernel (there should only be 1)
cp $root/boot/vmlinuz-* $boot/vmlinuz

echo "Building initrd..."
pwd="$(pwd)"
cd $root || exit 1
# Command which builds the initramfs
find . | cpio -H newc -o | gzip -c > $pwd/$boot/initrd || exit 1
cd "$pwd"

echo "Setting owner on extracted files..."
chown -R $SUDO_UID:$SUDO_GID $boot

echo "Build Finished"

