#!/bin/sh

set -e

# This script runs in the public router netns

VLAN_DEVICE=veth-br
WAN_DEVICE=vlan-uplink
CGN_DEVICE=veth-priv

# General network preferences
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/default/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 1 > /proc/sys/net/ipv6/conf/default/forwarding
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
echo 0 > /proc/sys/net/ipv6/conf/default/accept_ra
echo 0 > /proc/sys/net/ipv6/conf/all/accept_ra

# General network setup
ip link set lo up
ip addr add 85.239.127.193/32 dev lo
ip addr add 146.0.105.65/32 dev lo
ip addr add 2a02:238:f02a:ffff:1::/128 dev lo

# Do not route bogon IP space
ip route add unreachable 10.0.0.0/8
ip route add unreachable 172.16.0.0/12
ip route add unreachable 192.168.0.0/16
ip route add unreachable 100.64.0.0/10

# Do not route our own IP space, unless we have a more specific
ip route add unreachable 85.239.127.192/26
ip route add unreachable 146.0.105.64/26

# Don't do any connection tracking in the public IP router
iptables -t raw -I PREROUTING -j NOTRACK
ip6tables -t raw -I PREROUTING -j NOTRACK

# Setup the WAN interface
ip link set ${WAN_DEVICE} up
ip route add 85.239.127.254 dev ${WAN_DEVICE}
ip route add 146.0.105.126 dev ${WAN_DEVICE}
ip route add 2a02:238:1:f02a::1 dev ${WAN_DEVICE}

echo 1 > /proc/sys/net/ipv6/conf/${WAN_DEVICE}/proxy_ndp
echo 0 > /proc/sys/net/ipv6/neigh/${WAN_DEVICE}/proxy_delay
ip neigh add proxy 2a02:238:1:f02a::2 dev ${WAN_DEVICE}
ip route add default via 146.0.105.126 dev ${WAN_DEVICE}
ip route add default via 2a02:238:1:f02a::1 dev ${WAN_DEVICE}

for i in $(seq 65 125); do
	ip neigh add proxy 146.0.105.$i dev ${WAN_DEVICE}
done
for i in $(seq 193 253); do
	ip neigh add proxy 85.239.127.$i dev ${WAN_DEVICE}
done

# Setup the CGN interface
ip link set ${CGN_DEVICE} up
echo 1 > /proc/sys/net/ipv6/conf/${CGN_DEVICE}/disable_ipv6
echo 1 > /proc/sys/net/ipv4/conf/${CGN_DEVICE}/proxy_arp
echo 0 > /proc/sys/net/ipv4/neigh/${CGN_DEVICE}/proxy_delay

for i in $(seq 112 119); do
	ip route add 146.0.105.$i dev ${CGN_DEVICE}
done

# Make sure the vlan interface is up
ip link set ${VLAN_DEVICE} up
echo 1 > /proc/sys/net/ipv6/conf/${VLAN_DEVICE}/disable_ipv6
# And setup customer facing vlans
cd "`dirname $0`"/../python
python2 inter_vlan_router.py --mode public --iface ${VLAN_DEVICE} --apply
