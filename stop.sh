#!/bin/sh

set -e

MAIN_DEVICE=eth0

ip netns del router-priv
ip netns del router-pub

ip link set br0 down
brctl delif br0 eth0
brctl delbr br0
ip link set ${MAIN_DEVICE} down
