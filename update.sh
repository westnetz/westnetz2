#!/bin/sh

set -e

. "`dirname $0`"/settings

echo "=== On public router ===" >&2
ip netns exec router-pub "`dirname $0`/scripts/router-public-update.sh"
echo
echo "=== On private router ===" >&2
ip netns exec router-priv "`dirname $0`/scripts/router-private-update.sh"

`dirname $0`/scripts/setup-qos.sh
