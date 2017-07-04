# Minimal Ubuntu VM for Ansible setup

This repository is my automation for building virtual and physical OS base
images for Ubuntu.

It is focused on turning control over to a configuration management tool
(I like Ansible at the moment) as soon as possible. This is to allow rapid
development and iteration, regardless of the final provisioning and management
disposition of the image (i.e. conventional, config-managed, immutable).

# Usage

There are several ways this can be used - all are valid.

## Disk Image Building

`./build.sh` creates `diskimage.qcow2` which contains the minimal disk image
needed to allow SSH root access (by the current user id_rsa) so it can be
further provisioned via SSH.

The result of `./build.sh` is a booted VM listening on port 10022, which can
then be provisioned.

The idea is to use your normal ansible provisioning scripts to build up the
initial disk image, so configuration changes propagated dynamically can be
reflected in built disks.

Note: after boot the file `root.password` is emitted into the build directory
containing a randomly generated root password for the machine.

## Live Booting

Technically speaking the resultant disk image will work as a provisioning
system. By PXE booting the `vmlinuz` and `initrd` on a physical VM, the system
will provision the disk (simplistically) and then switch-root into the running
system, making it available over SSH for further provisioning with unique
SSH host keys and `/etc/machine-id` already set.

By passing `bootstrap_root_key` and `bootstrap_root_password` as PXE parameters
the root key and root password can be set to unique (ephemeral) values each
time.

# Motivation

There's lots of projects oriented towards solving this problem, and none of them
really suited the way I like to work. 

With this repository I'm choosing a workflow which I generally find pleasant - 
quickly booting a VM with KVM this way and building it up into a custom Ubuntu 
based system strikes, for me, a nice balance between codifying my configuration
choices reproducibly (Ansible) and letting me freely experiment and explore to
work out what I want to do.
