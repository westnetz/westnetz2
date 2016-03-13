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

ip link set br-int down
brctl delif br-int ${MAIN_DEVICE}
brctl delbr br-int
ip link set ${MAIN_DEVICE} down
