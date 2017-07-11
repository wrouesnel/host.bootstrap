
Basic Ansible playbook to confirm the provisioning of the bootstrap host.

This playbook does nothing except update the already bootstrapped packages, so
its not very useful by itself. You should customize and extend the image here
to do the real configuration.

Run as:
```
$ ansible-playbook -i inventory bootstrap.yml --tags=!bootstrap-finalize
```

Note: we exclude finalize because you will lose access to the VM as root if you
don't customize the setup.
