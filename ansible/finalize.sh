#!/bin/sh
# Host finalization script for bootstrapped images. Clear SSH host keys,
# wipe root password and authorized_keys.

echo "Wiping SSH host keys..."
rm -rf /etc/ssh/ssh_host_*

echo "Wiping /root/.ssh/authorized_keys"
rm -r /root/.ssh/authorized_keys

echo "Disabling root password"
passwd -l root

echo "Shutting down"
systemctl poweroff
