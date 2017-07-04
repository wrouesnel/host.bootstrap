#!/bin/bash

output_img=diskimage.qcow2
output_size=${output_size:-100G}

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

kvm -m 2048M -drive file=${output_img},cache=unsafe \
    -netdev user,id=network0,hostfwd=tcp::10022-:22 -device virtio-net-pci,netdev=network0 \
    -kernel vmlinuz -initrd initrd \
    -append "console=tty0 console=ttyS0,115200n8 bootstrap_root_password=$root_password bootstrap_root_key=$root_key $@" \
    -vnc :0 \
    -serial stdio
