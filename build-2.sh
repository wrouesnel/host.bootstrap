#!/bin/bash

. settings.sh

[ -e "$output_img" ] && rm -v -f "$output_img"

qemu-img create -f qcow2 ${output_img} ${output_size}

# generate and emit a root password
if [ -z "$root_password" ]; then
    root_password="$(pwgen 48 1)"
fi

if [ -z "$root_key" ]; then
    root_key="$(cat $HOME/.ssh/id_rsa.pub | base64 -w0)"
fi
echo $root_password > root.password

echo "Temporary Root Password: $root_password"
echo "SSH listening on 10022"
echo "Remember to clear SSH host keys once disk build is finished."

kvm ${kvm_defaults[@]} \
    -m 4096M \
    -drive file="${output_img}",cache=unsafe,if=none,id=drive-virtio-disk0 \
    -device virtio-blk-pci,scsi=off,bus=pci.0,addr=0x7,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1 \
    -netdev user,id=network0,hostfwd=tcp::10022-:22 -device virtio-net-pci,netdev=network0 \
    -kernel $boot/vmlinuz -initrd $boot/initrd \
    -append "console=tty0 console=ttyS0,115200n8 bootstrap_root_password=$root_password bootstrap_root_key=$root_key $@" \
    -vnc :0 \
    -serial stdio
