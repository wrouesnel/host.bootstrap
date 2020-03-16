"""
Module to handle mounting qcow2 images with qemu-nbd reliably.
"""
ANSIBLE_METADATA = {
    "status": ["preview"],
    "supported_by": "community",
    "version": "0.1",
}

DOCUMENTATION = """
module: qemu_nbd
version_added: "2.9"
short_description: Mount a disk image to a local nbd device and return the device name.
options:
  name:
    required: true
    default: None
    description:
      - Name of the file or device to map
  format:
    required: false
    default: None
    description:
      - Specify an explicit format for the disk image.
  state:
    required: true
    default: None
    description:
      - If set to 'present' then the specified file is mapped to a device and the
        device name returned.
      - If set to 'absent' then the specified fie is unmapped from a device and
        the device returned.
author: "wrouesnel@wrouesnel.com"
"""

import os
import psutil
import re
import subprocess
import time
import errno
import signal
import shlex
from ansible.module_utils.basic import AnsibleModule

# DEVMAPPER = "/dev/mapper"
# PARTNUM_RX = re.compile(".*(\d+)$")

DEVNBD = "nbd"
QEMUNBD = "qemu-nbd"

module = AnsibleModule(
    argument_spec=dict(
        name=dict(required=True, type="str", default=None),
        state=dict(required=True, type="str", default=None),
        format=dict(required=False, type="str", default="qcow2"),
    ),
    supports_check_mode=False,
)

params = module.params
name = params["name"]
state = params["state"]
format = params["format"]

result = {}

if state == "present":
    present_nbds = set()

    for e in os.listdir("/dev"):
        if e.startswith(DEVNBD):
            present_nbds.add("/dev/%s" % (e,))

    if len(present_nbds) == 0:
        module.fail_json(msg="no nbd block devices found. Is the nbd kernel module loaded?")

    available_nbds = []

    for device in present_nbds:
        try:
            f = os.open(device, os.O_EXCL)
            available_nbds.append(device)
        except OSError:
            continue

    if len(available_nbds) == 0:
        module.fail_json(msg="no nbd block devices could be opened")

    # Loop until we succeed at mounting with an available nbd
    cmd = []
    success = False
    last_error = None
    attempted_nbds = []
    for device in available_nbds:
        try:
            attempted_nbds.append(name)
            cmd = [
                QEMUNBD,
                "--discard=unmap",
                "--detect-zeroes=unmap",
                "--persistent",
                "-f",
                format,
                "-c",
                device,
                name,
            ]
            subprocess.check_call(cmd)
            # Update result data if we succeeded.
            result["device"] = device
            result["command"] = cmd
            result["shell_command"] = " ".join(cmd)
            result["changed"] = True
            # Notify success outside the loop
            success = True
            break
        except subprocess.CalledProcessError as ex:
            print(ex.stdout, ex.output)
            last_error = ex.stdout.read()

    if not success:
        module.fail_json(msg="qemu-nbd failed to bind to any available device", 
            attempted_nbds=attempted_nbds, last_error=last_error)

elif state == "absent":
    # Find a qemu-nbd started with the correct name.
    result["changed"] = False
    for p in psutil.process_iter():
        # TODO: this line seems to work differently depending on psutil?
        cmdline = p.cmdline
        if callable(cmdline):
            cmdline = cmdline()
        if len(cmdline) == 0:
            continue
        if QEMUNBD not in cmdline[0]:
            continue
        if cmdline[-1] != name:
            continue
        process_gone = False
        try:
            os.kill(p.pid, signal.SIGTERM)
        except OSError as e:
            if e.errno == errno.ESRCH:
                process_gone = True
            elif e.errno == errno.EPERM:
                module.fail_json(
                    msg="Permission denied when trying to terminate qemu-nbd process"
                )

        while not process_gone:
            try:
                os.kill(p.pid, 0)
            except OSError as e:
                if e.errno == errno.ESRCH:
                    process_gone = True
                elif e.errno == errno.EPERM:
                    module.fail_json(
                        msg="Permission denied when trying to terminate qemu-nbd process"
                    )
            # Sleep 100ms to let the process shutdown
            time.sleep(0.1)

        result["changed"] = True
        break
        # Wait for the process to die
else:
    module.fail_json(msg="state must be one of 'present' or 'absent'")

module.exit_json(**result)
