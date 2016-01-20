#!/bin/sh

set -e

. "`dirname $0`"/../settings

# This script runs in the private/nat router netns

cd "`dirname $0`"/../python
${PYTHON} inter_vlan_router.py --mode private --iface ${RTR_PRIVATE_TRUNK} --apply
