#!/bin/sh

set -e

# This script runs in the private/nat router netns

VLAN_DEVICE=veth-br
WAN_DEVICE=veth-pub

# General network preferences
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/default/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

# General network setup
ip link set lo up
# XXX: MAGIC
ip addr add 146.0.105.112/32 dev lo # TODO: maybe use dedicated IP for loopback;
                                    # IP is needed as ARP-source towards router-pub
                                    # and as ICMP-Error source

# WAN setup
ip link set ${WAN_DEVICE} up
ip link add dummy-nat type dummy
ip link set dummy-nat up
echo 1 > /proc/sys/net/ipv6/conf/${WAN_DEVICE}/disable_ipv6
echo 0 > /proc/sys/net/ipv4/neigh/${WAN_DEVICE}/proxy_delay
# XXX: MAGIC
ip route add 146.0.105.65 dev ${WAN_DEVICE}
ip route add default via 146.0.105.65
for i in $(seq 112 119); do
	ip neigh add proxy 146.0.105.$i dev ${WAN_DEVICE}
	ip route add 146.0.105.$i/32 dev dummy-nat
done

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
-A POSTROUTING -s 172.19.128.0/17 -o ${WAN_DEVICE} -j SNAT --to-source 146.0.105.112-146.0.105.119 --persistent
COMMIT
#
EOF
iptables-restore < /tmp/router-private-iptables.conf

# Conntrack settings
echo 262144 > /proc/sys/net/netfilter/nf_conntrack_max
echo 90 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout
echo 660 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout_stream

# Make sure the vlan interface is up
ip link set ${VLAN_DEVICE} up
echo 1 > /proc/sys/net/ipv6/conf/${VLAN_DEVICE}/disable_ipv6
# And setup customer facing vlans
cd "`dirname $0`"/../python
python2 inter_vlan_router.py --mode private --iface ${VLAN_DEVICE} --apply
