#!/bin/sh

set -e

. "`dirname $0`"/../settings

# This script runs in the public router netns

# General network preferences
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/default/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 1 > /proc/sys/net/ipv6/conf/default/forwarding
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
echo 0 > /proc/sys/net/ipv6/conf/default/accept_ra
echo 0 > /proc/sys/net/ipv6/conf/all/accept_ra

ip link add dummy-static type dummy
ip link set dummy-static up

# General network setup
ip link set lo up
for IP in ${RTR_PUBLIC_LOOPBACK_IPV4}; do
	ip -4 addr add ${IP}/32 dev lo
done
for IP in ${RTR_PUBLIC_LOOPBACK_IPV6}; do
	ip -6 addr add ${IP}/128 dev lo
done

# Do not route bogon IP space
ip route add unreachable 10.0.0.0/8
ip route add unreachable 172.16.0.0/12
ip route add unreachable 192.168.0.0/16
ip route add unreachable 100.64.0.0/10

# Do not route our own IP space, unless we have a more specific
for NET in ${RTR_PUBLIC_OWN_NETS_V4}; do
	ip route add unreachable ${NET}
done
for NET in ${RTR_PUBLIC_OWN_NETS_V6}; do
	ip -6 route add unreachable ${NET}
done

# Don't do any connection tracking in the public IP router
iptables -t raw -I PREROUTING -j NOTRACK
ip6tables -t raw -I PREROUTING -j NOTRACK
# Enable rp_filter for IPv6
ip6tables -t raw -A PREROUTING -m rpfilter --invert -j DROP

# Setup the WAN interface
ip link set ${RTR_PUBLIC_UPLINK} up
if [ -n "${RTR_PUBLIC_UPLINK_ONLINK_IPV4}" ]; then
	for IP in ${RTR_PUBLIC_UPLINK_ONLINK_IPV4}; do
		ip -4 route add ${IP} dev ${RTR_PUBLIC_UPLINK}
	done
fi
if [ -n "${RTR_PUBLIC_UPLINK_ONLINK_IPV6}" ]; then
	for IP in ${RTR_PUBLIC_UPLINK_ONLINK_IPV6}; do
		ip -6 route add ${IP} dev ${RTR_PUBLIC_UPLINK}
	done
fi

if [ -n "${RTR_PUBLIC_UPLINK_PROXY_IPV6}" ]; then
	echo 1 > /proc/sys/net/ipv6/conf/${RTR_PUBLIC_UPLINK}/proxy_ndp
	echo 0 > /proc/sys/net/ipv6/neigh/${RTR_PUBLIC_UPLINK}/proxy_delay

	for IP in ${RTR_PUBLIC_UPLINK_PROXY_IPV6}; do
		# XXX: Do we need a route?
		ip -6 neigh add proxy ${IP} dev ${RTR_PUBLIC_UPLINK}
	done
fi

if [ -n "${RTR_PUBLIC_UPLINK_PROXY_IPV4}" ]; then
	echo 1 > /proc/sys/net/ipv4/conf/${RTR_PUBLIC_CGN_DOWNLINK}/proxy_arp
	echo 0 > /proc/sys/net/ipv4/neigh/${RTR_PUBLIC_CGN_DOWNLINK}/proxy_delay

	for IP in ${RTR_PUBLIC_UPLINK_PROXY_IPV4}; do
		ip neigh add proxy ${IP} dev ${RTR_PUBLIC_UPLINK}
	done
fi

if [ -n "${RTR_PUBLIC_UPLINK_OWN_IPV4}" ]; then
	for IP in ${RTR_PUBLIC_UPLINK_OWN_IPV4}; do
		ip -4 addr add ${IP} dev ${RTR_PUBLIC_UPLINK}
	done
fi

if [ -n "${RTR_PUBLIC_UPLINK_OWN_IPV6}" ]; then
	for IP in ${RTR_PUBLIC_UPLINK_OWN_IPV6}; do
		ip -6 addr add ${IP} dev ${RTR_PUBLIC_UPLINK}
	done
fi

if [ -n "${RTR_PUBLIC_UPLINK_GW_IPV4}" ]; then
	ip -4 route add default via ${RTR_PUBLIC_UPLINK_GW_IPV4} dev ${RTR_PUBLIC_UPLINK}
fi

if [ -n "${RTR_PUBLIC_UPLINK_GW_IPV6}" ]; then
	ip -6 route add default via ${RTR_PUBLIC_UPLINK_GW_IPV6} dev ${RTR_PUBLIC_UPLINK}
fi

# Setup the CGN interface
ip link set ${RTR_PUBLIC_CGN_DOWNLINK} up
echo 1 > /proc/sys/net/ipv6/conf/${RTR_PUBLIC_CGN_DOWNLINK}/disable_ipv6

for IP in ${RTR_PRIVATE_NAT_ALL}; do
	ip route add ${IP} dev ${RTR_PUBLIC_CGN_DOWNLINK}
done

# Make sure the vlan interface is up
ip link set ${RTR_PUBLIC_TRUNK} up
echo 1 > /proc/sys/net/ipv6/conf/${RTR_PUBLIC_TRUNK}/disable_ipv6
# And setup customer facing vlans
cd "`dirname $0`"/../python
${PYTHON} inter_vlan_router.py --mode public --iface ${RTR_PUBLIC_TRUNK} --apply --spec /etc/westnetz.json
if [ -d "/etc/westnetz.service.public" ]; then
	runsvdir /etc/westnetz.service.public ...................................................... > /dev/null 2>&1 < /dev/null &
	echo "$!" > "/run/runsvdir-public.pid"
fi
