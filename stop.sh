#!/bin/sh

set -e

. "`dirname $0`"/settings
. "`dirname $0`"/tools

if namespace_exists router-pub || namespace_exists router-priv; then
	:
else
	echo "Westnetz2 is not running" >&2
	exit 0
fi

ip netns del router-priv
ip netns del router-pub

ip link set br0 down
brctl delif br0 ${MAIN_DEVICE}
brctl delbr br0
ip link set ${MAIN_DEVICE} down
