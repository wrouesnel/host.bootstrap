"""
Ansible module to map and unmap loopback disks with kpartx
"""

ANSIBLE_METADATA = {
    "status": ["preview"],
    "supported_by": "community",
    "version": "0.1",
}

DOCUMENTATION = """
module: kpartx
version_added: "2.9"
short_description: Map and unmap disk imags with kpartx
options:
  name:
    required: true
    default: None
    description:
      - Name of the file or device to map
  state:
    required: true
    default: None
    description:
      - If set to 'present' then the specified named is mapped and the partition
        mapping returned.
      - If set to 'absent' then the specified filesystem image is unmapped and
        its loopback devices deleted.
author: "wrouesnel@wrouesnel.com"
"""

import os
import re
import subprocess
from ansible.module_utils.basic import AnsibleModule

DEVMAPPER = "/dev/mapper"
# PARTNUM_RX = re.compile(".*(\d+)$")

module = AnsibleModule(
    argument_spec=dict(
        name=dict(required=True, type="str", default=None),
        state=dict(required=True, type="str", default=None),
    ),
    supports_check_mode=False,
)

params = module.params
name = params["name"]
state = params["state"]

if state not in ("present", "absent"):
    module.fail_json(msg="state must be set to either 'present' or 'absent'")

if name == "":
    module.fail_json(msg="name cannot be blank")

result = {}

if state == "present":
    try:
        output = subprocess.check_output(["kpartx", "-s", "-v", "-a", name])
    except subprocess.CalledProcessError as e:
        module.fail_json(
            msg="kpartx invocation failed",
            return_code=e.returncode,
            stdout=e.stdout,
            stderr=e.stderr,
        )
    present_mappings = []
    for l in output.decode("utf8").split("\n"):
        if l.strip() == "":
            continue
        lt = l.split()
        mapper_path = os.path.join(DEVMAPPER, lt[2])
        # m = PARTNUM_RX.match(lt[2])
        # if m is None:
        #     module.fail_json(
        #         msg="error trying to parse partition number from %s" % (lt[2],)
        #     )
        present_mappings.append(mapper_path)
    result["present"] = present_mappings
    result["changed"] = True if len(present_mappings) > 0 else False

elif state == "absent":
    try:
        output = subprocess.check_output(["kpartx", "-s", "-v", "-d", name])
    except subprocess.CalledProcessError as e:
        module.fail_json(
            msg="kpartx invocation failed",
            return_code=e.returncode,
            stdout=e.stdout,
            stderr=e.stderr,
        )
    removed_mappings = []
    for l in output.decode("utf8").split("\n"):
        if l.strip() == "":
            continue
        mapper_path = os.path.join(DEVMAPPER, l.split()[-1])
        removed_mappings.append(mapper_path)
    result["removed"] = removed_mappings
    result["changed"] = True if len(removed_mappings) > 0 else False

else:
    module.fail_json(msg="state must be set to either 'present' or 'absent'")

module.exit_json(**result)
