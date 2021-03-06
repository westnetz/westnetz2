#!/bin/sh

set -e

. "`dirname $0`"/../settings

# This script runs in the private/nat router netns

# General network preferences
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/default/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

# General network setup
ip link set lo up
ip addr add ${RTR_PRIVATE_LOOPBACK}/32 dev lo  # IP is needed as ARP-source towards router-pub
                                               # and as ICMP-Error source

# WAN setup
ip link set ${RTR_PRIVATE_UPLINK} up
echo 1 > /proc/sys/net/ipv6/conf/${RTR_PRIVATE_UPLINK}/disable_ipv6
if [ x"$NAT_EXTERNAL" != x"yes" ]; then
	ip link add dummy-nat type dummy
	ip link set dummy-nat up
	echo 0 > /proc/sys/net/ipv4/neigh/${RTR_PRIVATE_UPLINK}/proxy_delay
	ip route add ${RTR_PRIVATE_GATEWAY} dev ${RTR_PRIVATE_UPLINK}
	ip route add default via ${RTR_PRIVATE_GATEWAY}
	for IP in ${RTR_PRIVATE_NAT_ALL}; do
		ip neigh add proxy ${IP} dev ${RTR_PRIVATE_UPLINK}
		ip route add ${IP}/32 dev dummy-nat
	done
else
	ip addr add ${NAT_PRIV_CGN_OWN} dev ${RTR_PRIVATE_UPLINK}
	ip route add default via ${NAT_PRIV_CGN_CGN}
fi

if [ x"$NAT_EXTERNAL" != x"yes" ]; then
	# NAT and firewall config
	cat << EOF > /tmp/router-private-iptables.conf
#
*filter
:INPUT ACCEPT
:FORWARD ACCEPT
:OUTPUT ACCEPT
:customer_filter -
-A FORWARD -d 172.19.128.0/17 -j customer_filter
-A FORWARD -s 172.19.128.0/17 -d 172.19.128.0/17 -j LOG --log-prefix c2c
-A FORWARD -s 172.19.128.0/17 -d 172.19.128.0/17 -j REJECT --reject-with icmp-net-prohibited
-A customer_filter -m state --state INVALID,NEW,UNTRACKED -j REJECT --reject-with icmp-net-prohibited
COMMIT
#
*nat
:PREROUTING ACCEPT
:INPUT ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT
-A POSTROUTING -s 172.19.128.0/17 -o ${RTR_PRIVATE_UPLINK} -j SNAT --to-source ${RTR_PRIVATE_NAT_FIRST}-${RTR_PRIVATE_NAT_LAST} --persistent
COMMIT
#
EOF
	iptables-restore < /tmp/router-private-iptables.conf

	for IP in ${RTR_PRIVATE_NAT_ALL}; do
		iptables -A FORWARD -m state --state NEW -d ${IP} -j DROP
	done
else
	cat << EOF > /tmp/router-private-iptables.conf
#
*filter
:INPUT ACCEPT
:FORWARD ACCEPT
:OUTPUT ACCEPT
:customer_filter -
-A FORWARD -s 172.19.128.0/17 -d 172.19.128.0/17 -j LOG --log-prefix c2c
-A FORWARD -s 172.19.128.0/17 -d 172.19.128.0/17 -j REJECT --reject-with icmp-net-prohibited
COMMIT
#
*nat
:PREROUTING ACCEPT
:INPUT ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT
COMMIT
#
EOF
	iptables-restore < /tmp/router-private-iptables.conf
	# If NAT is external, don't do conntrack
	iptables -t raw -I PREROUTING -j NOTRACK
	ip6tables -t raw -I PREROUTING -j NOTRACK
fi

ip6tables -A INPUT   -p icmpv6 --icmpv6-type router-solicitation  -m frag -j DROP
ip6tables -A INPUT   -p icmpv6 --icmpv6-type router-advertisement -m frag -j DROP
ip6tables -A FORWARD -p icmpv6 --icmpv6-type router-solicitation  -m frag -j DROP
ip6tables -A FORWARD -p icmpv6 --icmpv6-type router-advertisement -m frag -j DROP

# Conntrack settings
echo 262144 > /proc/sys/net/netfilter/nf_conntrack_max
echo 90 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout
echo 660 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout_stream

# Make sure the vlan interface is up
ip link set ${RTR_PRIVATE_TRUNK} up
echo 1 > /proc/sys/net/ipv6/conf/${RTR_PRIVATE_TRUNK}/disable_ipv6
# And setup customer facing vlans
cd "`dirname $0`"/../python
${PYTHON} inter_vlan_router.py --mode private --iface ${RTR_PRIVATE_TRUNK} --apply --spec /etc/westnetz.json
if [ -d "/etc/westnetz.service.private" ]; then
	runsvdir /etc/westnetz.service.private ...................................................... > /dev/null 2>&1 < /dev/null &
	echo "$!" > "/run/runsvdir-private.pid"
fi
${PYTHON} dhcp_setup.py --iface ${RTR_PRIVATE_TRUNK} --spec /etc/westnetz.json
