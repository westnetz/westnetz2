#!/usr/bin/env python2

import sys, os
import json
import argparse
from jinja2 import Template

template = Template('''#!/bin/sh
{% set main_dev = env.MAIN_DEVICE %}
# 3999: default class (i.e. misconfiguration + ARP/LLDP/v6LL traffic)
# 3998: internal traffic
# 3997: internet traffic

netif_base() {
	dev="$1"
	bw="$2"

	ip link  set dev $dev up
	ip link  set dev $dev txqueuelen 128
	tc qdisc del dev $dev root >/dev/null 2>&1
	tc qdisc add dev $dev root handle 1: hfsc default 3999
	tc class add dev $dev parent 1:  classid 1:1    hfsc sc rate 900Mbit ul rate 900MBit
	tc class add dev $dev parent 1:1 classid 1:3999 hfsc ls rate  10MBit ul rate  10MBit
	tc class add dev $dev parent 1:1 classid 1:3998 hfsc ls rate  10Mbit ul rate 750Mbit
	tc class add dev $dev parent 1:1 classid 1:3997 hfsc ls rate  10Mbit ul rate     $bw
	tc qdisc add dev $dev parent 1:3999 handle 3999: sfq
	tc qdisc add dev $dev parent 1:3998 handle 3998: sfq
}
netif_base {{ main_dev }} {{ env.BW_DOWNLOAD }}
netif_base ifb0 {{ env.BW_UPLOAD }}

netif_egress_ifb() {
	dev="$1"
	tc_match_all="u32 match u32 0 0"
	tc qdisc  del dev $dev root >/dev/null 2>&1
	tc qdisc  add dev $dev root handle 1: prio priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
	tc filter add dev $dev parent 1:0 protocol ip   priority 10 $tc_match_all flowid 1: action mirred egress redirect dev ifb0
	tc filter add dev $dev parent 1:0 protocol ipv6 priority 20 $tc_match_all flowid 1: action mirred egress redirect dev ifb0
}
netif_egress_ifb veth-priv
netif_egress_ifb veth-pub

tc_inttraf() {
	dev="$1"; shift
	dir="$1"; shift
{% for network in env.RTR_PRIVATE_OWN_NETS.split() + env.RTR_PUBLIC_OWN_NETS_V4.split() %}
	tc filter add dev $dev parent 1:0 protocol ip priority {{ 100 + loop.index0 }} u32 match ip  $dir {{ network }} flowid 1:3998
{% endfor %}
{% for network in env.RTR_PUBLIC_OWN_NETS_V6.split() %}
	tc filter add dev $dev parent 1:0 protocol ipv6 priority {{ 200 + loop.index0 }} u32 match ip6 $dir {{ network }} flowid 1:3998
{% endfor %}
}

tc_inttraf ifb0 dst
tc_inttraf {{ main_dev }} src

tc_vlan() {
	dev="$1"; shift
	vlanid="$1"; shift
	rate="$1"; shift
	extra="$*"

	tc class  add dev $dev parent 1:3997 classid 1:$vlanid hfsc \
		$extra ls rate 10Mbit ul rate $rate
	tc qdisc  add dev $dev parent 1:$vlanid handle $vlanid: sfq

	tc filter add dev $dev parent 1:0 protocol ip   priority 300 basic match meta '(' vlan eq $vlanid ')' flowid 1:$vlanid
	tc filter add dev $dev parent 1:0 protocol ipv6 priority 400 basic match meta '(' vlan eq $vlanid ')' flowid 1:$vlanid
}

{% for klass,info in classes|dictsort -%}
{%  set upstream   =   info.upstream|default('21Mbit') -%}
{%  set downstream = info.downstream|default('21Mbit') -%}
tc_vlan ifb0 {{ klass }} {{ upstream   }} {% if info.upstream_guarantee   %} rt rate {{ info.upstream_guarantee   }} {% endif %} # up
tc_vlan {{ main_dev }} {{ klass }} {{ downstream }} {% if info.downstream_guarantee %} rt rate {{ info.downstream_guarantee }} {% endif %} # down

{% endfor %}

if [ -x "/etc/westnetz.qos.hook" ]; then
	/etc/westnetz.qos.hook
fi

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

print template.render(classes=spec['classes'], env=os.environ)
