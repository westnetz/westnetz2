#!/bin/sh

set -e

cd "`dirname $0`/python"
echo "=== On public router ===" >&2
ip netns exec router-pub python2 inter_vlan_router.py --mode public --iface veth-br "$@"
echo
echo "=== On private router ===" >&2
ip netns exec router-priv python2 inter_vlan_router.py --mode private --iface veth-br "$@"
