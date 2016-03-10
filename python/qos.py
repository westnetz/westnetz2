#!/usr/bin/env python2

import sys, os
import json
import argparse
from jinja2 import Template

template = Template('''#!/bin/sh

# 3999: default class (i.e. misconfiguration + ARP/LLDP/v6LL traffic)
# 3998: internal traffic

netif_base() {
	dev="$1"
	bw="$2"

	ip link  set dev $dev up
	ip link  set dev $dev txqueuelen 128
	tc qdisc del dev $dev root &>/dev/null
	tc qdisc add dev $dev root handle 1: hfsc default 3999
	tc class add dev $dev parent 1:  classid 1:1    hfsc sc rate     $bw ul rate     $bw
	tc class add dev $dev parent 1:1 classid 1:3999 hfsc ls rate   1Mbit ul rate   1Mbit
	tc class add dev $dev parent 1:1 classid 1:3998 hfsc ls rate 100Mbit ul rate 750Mbit
	tc qdisc add dev $dev parent 1:3999 handle 3999: sfq
	tc qdisc add dev $dev parent 1:3998 handle 3998: sfq
}
netif_base eth0 28MBit
netif_base ifb0 28MBit

netif_egress_ifb() {
	dev="$1"
	tc_match_all="u32 match u32 0 0"
	tc qdisc  add dev $dev root handle 1: prio priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
	tc filter add dev $dev parent 1:0 protocol ip   priority 10 $tc_match_all flowid 1: action mirred egress redirect dev ifb0
	tc filter add dev $dev parent 1:0 protocol ipv6 priority 20 $tc_match_all flowid 1: action mirred egress redirect dev ifb0
}
netif_egress_ifb veth-priv
netif_egress_ifb veth-pub

tc_vlan() {
	dev="$1"; shift
	vlanid="$1"; shift
	rate="$1"; shift
	dir="$1"; shift
	extra="$*"

	tc class  add dev $dev parent 1:1 classid 1:$vlanid hfsc \
		$extra ls rate 10Mbit ul rate $rate
	tc qdisc  add dev $dev parent 1:$vlanid handle $vlanid: sfq

	tc filter add dev $dev parent 1:0 protocol ip   priority 10 u32 match ip  $dir 172.19.0.0/16    flowid 1:3998
	tc filter add dev $dev parent 1:0 protocol ip   priority 11 u32 match ip  $dir 185.142.180.0/22 flowid 1:3998
	tc filter add dev $dev parent 1:0 protocol ipv6 priority 12 u32 match ip6 $dir 2a07:2ec0::/29   flowid 1:3998

	tc filter add dev $dev parent 1:0 protocol ip   priority 20 basic match meta '(' vlan eq $vlanid ')' flowid 1:$vlanid
	tc filter add dev $dev parent 1:0 protocol ipv6 priority 21 basic match meta '(' vlan eq $vlanid ')' flowid 1:$vlanid
}

{% for klass,info in classes|dictsort -%}
{%  set upstream   =   info.upstream|default('21Mbit') -%}
{%  set downstream = info.downstream|default('21Mbit') -%}
tc_vlan ifb0 {{ klass }} {{ upstream   }} dst {% if info.upstream_guarantee   %} rt rate {{ info.upstream_guarantee   }} {% endif %} # up
tc_vlan eth0 {{ klass }} {{ downstream }} src {% if info.downstream_guarantee %} rt rate {{ info.downstream_guarantee }} {% endif %} # down

{% endfor %}
''')

##############################################################################

argp = argparse.ArgumentParser(description = 'Westnetz QoS generator')
argp.add_argument('--spec', type = str)
args = argp.parse_args()

if args.spec is not None:
    specfd = open(args.spec, 'r')
else:
    specfd = sys.stdin
spec = json.load(specfd)

##############################################################################

print template.render(classes=spec['classes'])
