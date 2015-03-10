#!/usr/bin/env python2

import sys
import os, os.path
import yaml, json
import re
import argparse

##############################################################################

argp = argparse.ArgumentParser(description = 'Westnetz spec generator')
argp.add_argument('--numberplan', type = str)
argp.add_argument('--spec', type = str)
argp.add_argument('--debug', action = 'store_const', const = True)
args = argp.parse_args()

if args.numberplan is not None:
    fnnumberplan = args.numberplan
else:
    fnnumberplan = os.path.join(os.path.dirname(sys.argv[0]), '../Dokumente/Workdir/numberplan.yaml')

try:
    with open(fnnumberplan, 'r') as fd:
        numberplan = yaml.load(fd)
except IOError, e:
    sys.stderr.write('failed to load numberplan (%s): %s\n' % (fnnumberplan, str(e)))
    sys.exit(1)

fail = 0

##############################################################################

from ipaddr import IPv4Address, IPv4Network

def apply_template(ipnet, target, template):
    sub = template.get('sub', None)
    if sub is None: return

    tgt_sub = target.setdefault('sub', {})

    net = IPv4Network(ipnet)
    if args.debug:
        sys.stderr.write(str(net.ip) + '--' + str(net.broadcast) + '\n')

    def translate(addr, net):
        if addr > IPv4Address('128.0.0.0'):
            return IPv4Address(int(addr) - int(IPv4Address('255.255.255.255')) + int(net.broadcast))
        else:
            return IPv4Address(int(addr) + int(net.ip))

    for k, v in sub.items():
        key = '-'.join([str(translate(IPv4Address(a), net)) for a in k.split('-')])
        if key in tgt_sub:
            continue
        if args.debug:
            sys.stderr.write('\t' + key + '\n')
        tgt_sub[key] = v

##############################################################################

spec = {
    'classes': {
        '2137': { 'downstream': '40Mbit' },
    },
    'subnets': {
    },
}

def add_qos(qos_np, np):
    for ipnet, d in sorted(np.items()):
        if '/' not in ipnet: continue
        if 'sub' not in d: continue
        if 'qos' in d:
            qos_np.append(d)
        add_qos(qos_np, d['sub'])

roots = ['RFC1918', 'public']
qos_np = []
for r in roots:
    add_qos(qos_np, numberplan[r])

# qos_np = [
#   { sub: { <...subnets...> }, qos: { <...qos params...> } },
# ]

rfcre = re.compile('^172\.19\.(\d+)\.0/24$')
def numplan2qos(spec, np, enable = False, ignore_no_vlan = False):
    sub = np['sub']
    template = np.get('template', {})
    if not enable:
        return

    for ipnet, d in sorted(sub.items()):
        apply_template(ipnet, d, template)
        if ':' in ipnet:
            ipv = 'ipv6'
        else:
            ipv = 'ipv4'
            if ipnet.find('/') == -1:
                ipnet += '/32'

        if 'infrastructure' in d:
            continue

        m = rfcre.match(ipnet)
        if 'vlan' in d:
            vlan = int(d['vlan'])
        elif m is not None:
            vlan = int(m.group(1)) + 2000
            # sys.stderr.write('numberplan: auto-assigned %s VLAN id %d\n' % (ipnet, vlan))
        else:
            sys.stderr.write('numberplan: ignoring %s, no VLAN id!\n' % (ipnet))
            continue

        clsid = '%d' % (vlan)
        klass = spec['classes'].setdefault(clsid, {})
        ips = klass.setdefault(ipv, [])
        ips.append(ipnet)

        if ipnet in spec['subnets']:
            sys.stderr.write('CRITICAL: subnet %s assigned more than once!\n' % (ipnet))
            fail += 1
        net = spec['subnets'].setdefault(ipnet, {})
        net['vlan'] = vlan
        if 'gw' in d:
            net['gw'] = d['gw']
        if 'sub' in d:
            for ip, data in d['sub'].items():
                if 'infrastructure' in data:
                    addrlist = net.setdefault(data['infrastructure'], [])
                    addrlist.append(ip)

for np in qos_np:
    numplan2qos(spec, np, **np['qos'])

if args.spec is not None:
    specfd = open(args.spec, 'w')
else:
    specfd = sys.stdout

if fail > 0:
    sys.stderr.write('critical errors detected, refusing to write JSON\n')
    sys.exit(1)
else:
    json.dump(spec, specfd, indent = 2)
