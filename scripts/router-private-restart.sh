#!/bin/sh

set -e

. "`dirname $0`"/../settings

# This script runs in the private/nat router netns

cd "`dirname $0`"/../python
${PYTHON} dhcp_setup.py --iface ${RTR_PRIVATE_TRUNK} --spec /etc/westnetz.json --restart
