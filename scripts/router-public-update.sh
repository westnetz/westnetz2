#!/bin/sh

set -e

. "`dirname $0`"/../settings

# This script runs in the public router netns

cd "`dirname $0`"/../python
${PYTHON} inter_vlan_router.py --mode public --iface ${RTR_PUBLIC_TRUNK} --apply --spec /etc/westnetz.json
