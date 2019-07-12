# Host VM Builder

This repository is my automation for building virtual and physical OS base
images.

It is focused on turning control over to a configuration management tool
(I like Ansible at the moment) as soon as possible. This is to allow rapid
development and iteration, regardless of the final provisioning and management
disposition of the image (i.e. conventional, config-managed, immutable).

# Requirements

Packages:

```
yum
debootstrap
```

Python:

```
ansible==2.8
```