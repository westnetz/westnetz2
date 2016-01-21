#!/bin/sh

set -e

. "`dirname $0`"/settings
. "`dirname $0`"/tools

if namespace_exists router-pub || namespace_exists router-priv; then
	echo "Westnetz2 already set up" >&2
	exit 0
fi

# General network preferences
echo 0 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/default/accept_redirects
echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

ip link set ${MAIN_DEVICE} up

# Create the router namespaces
ip netns add router-pub
ip netns add router-priv

# Place uplink vlan in router-pub
ip link add link ${MAIN_DEVICE} ${RTR_PUBLIC_UPLINK} type vlan id ${UPLINK_VLAN}
ip link set ${RTR_PUBLIC_UPLINK} netns router-pub

# Interconnect router-pub to router-priv for public NAT-pool
ip link add ${RTR_PUBLIC_CGN_DOWNLINK} netns router-pub type veth peer name ${RTR_PRIVATE_UPLINK} netns router-priv

# Create Bridge for customer traffic to/from routers
brctl addbr br0
ip link add veth-pub type veth peer name ${RTR_PUBLIC_TRUNK} netns router-pub
brctl addif br0 veth-pub
ip link set veth-pub up
ip link add veth-priv type veth peer name ${RTR_PRIVATE_TRUNK} netns router-priv
brctl addif br0 veth-priv
ip link set veth-priv up
brctl addif br0 ${MAIN_DEVICE}
ip link set br0 up

# TODO: Setup QoS

# Setup the actual router configuration
ip netns exec router-pub "`dirname $0`/scripts/router-public-start.sh"
ip netns exec router-priv "`dirname $0`/scripts/router-private-start.sh"
