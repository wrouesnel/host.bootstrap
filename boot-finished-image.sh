#!/bin/bash
# Script which boots the VM without booting the kernel/initrd manually.

. settings.sh

kvm -m 2048M -drive file=${output_img},cache=unsafe \
    -netdev user,id=network0,hostfwd=tcp::10022-:22,hostfwd=tcp::16514-:16514 \
    -device virtio-net-pci,netdev=network0 \
    -serial stdio $@

#    -vnc :0 \
