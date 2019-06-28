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

    available_nbds = []

    for device in present_nbds:
        try:
            os.open(device, os.O_EXCL)
            available_nbds.append(device)
        except OSError:
            continue

    # Loop until we succeed at mounting with an available nbd
    cmd = []
    for device in available_nbds:
        try:
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
        except subprocess.CalledProcessError:
            continue
        break
    result["device"] = device
    result["command"] = cmd
    result["shell_command"] = " ".join(cmd)
    result["changed"] = True

elif state == "absent":
    # Find a qemu-nbd started with the correct name.
    result["changed"] = False
    for p in psutil.process_iter():
        # TODO: this line seems to work differently depending on psutil?
        cmdline = p.cmdline
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
