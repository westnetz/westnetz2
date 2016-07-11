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
# Turn of br_netfilter, bleh
modprobe bridge || true
echo 0 > /proc/sys/net/bridge/bridge-nf-call-arptables
echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables
echo 0 > /proc/sys/net/bridge/bridge-nf-call-ip6tables


ip link set ${MAIN_DEVICE} up
ip link set ${UPLINK_DEVICE} up

# Create the router namespaces
ip netns add router-pub
ip netns add router-priv

# Place uplink vlan in router-pub
ip link add link ${UPLINK_DEVICE} ${RTR_PUBLIC_UPLINK} type vlan id ${UPLINK_VLAN}
ip link set ${RTR_PUBLIC_UPLINK} netns router-pub

# Interconnect router-pub to router-priv for public NAT-pool
ip link add ${RTR_PUBLIC_CGN_DOWNLINK} netns router-pub type veth peer name ${RTR_PRIVATE_UPLINK} netns router-priv

# Create Bridge for customer traffic to/from routers
brctl addbr br-int
ip link add veth-pub type veth peer name ${RTR_PUBLIC_TRUNK} netns router-pub
brctl addif br-int veth-pub
ip link set veth-pub up
ip link add veth-priv type veth peer name ${RTR_PRIVATE_TRUNK} netns router-priv
brctl addif br-int veth-priv
ip link set veth-priv up
brctl addif br-int ${MAIN_DEVICE}
ip link set br-int up

# Turn off IGMP snooping on bridge
echo 0 > /sys/devices/virtual/net/br-int/bridge/multicast_snooping

if [ -x "/etc/westnetz.start.hook" ]; then
	/etc/westnetz.start.hook
fi

# Setup the actual router configuration
echo "=== On public router ===" >&2
ip netns exec router-pub "`dirname $0`/scripts/router-public-start.sh"
echo "=== On private router ===" >&2
ip netns exec router-priv "`dirname $0`/scripts/router-private-start.sh"

`dirname $0`/scripts/setup-qos.sh
