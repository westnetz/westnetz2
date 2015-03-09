
import sys
import os, os.path
import json
import re
import argparse

##############################################################################

custdict = {}
customers = []

class Customer(object):
    def __init__(self, vid, dictentry):
        self.vid = int(vid)
        self.dictentry = dictentry

        self.proxyif = False
        self.privnet = None
        self.extranets = []
        self.proxyips = []
        self.ipv6 = []
        custdict[self.vid] = self

    def __repr__(self):
        return '<%s vid=%d, proxyif=%r, privnet=%r, extranets=%r, proxyips=%r, ipv6=%r>' % (
                self.__class__.__name__, self.vid, self.proxyif, self.privnet, self.extranets,
                self.proxyips, self.ipv6)

    def iter_nets(self):
        if self.privnet:
            yield self.privnet
        for i in self.extranets:
            yield i

class Subnet4(object):
    rfcre = re.compile('^172\.19\.(\d+)\.0/24$')

    def __init__(self, ip, dictentry):
        vid = int(dictentry['vlan'])
        self.ip = ip
        self.masklen = int(ip.split('/')[1])
        self.rtrip = {}
        self.customer = customer = custdict[vid]
        self.gw = dictentry.get('gw', None)

        for rtr in ['cluster', 'router1', 'router2']:
            addrs = dictentry.get(rtr, [])
            if len(addrs) > 0:
                self.rtrip[rtr] = addrs[0]
            else:
                self.rtrip[rtr] = None

        m = Subnet4.rfcre.match(ip)
        if m is not None:
            self.name = '%d' % (vid)
            customer.privnet = self
        elif ip.endswith('/32'):
            customer.proxyif = True
            customer.proxyips.append(self)
        else:
            if len(customer.extranets) == 0 and vid >= 3000:
                self.name = '%d' % (vid)
            else:
                self.name = '%d-%d' % (vid, len(customer.extranets) + 2)
            customer.extranets.append(self)

    def __repr__(self):
        return '<%s ip=%s rtrip=%r gw=%r name=%s>' % (
                self.__class__.__name__, self.ip, self.rtrip,
                self.gw, repr(self.name) if hasattr(self, 'name') else 'N/A')

    def anyrtrip(self):
        for k, v in self.rtrip.items():
            if v is not None:
                return True
        return False
    def hasrtrip(self, host):
        return self.rtrip[host] is not None
    def getrtrip(self, host):
        return self.rtrip[host]

class Subnet6(object):
    def __init__(self, ip, dictentry):
        vid = int(dictentry['vlan'])
        self.ip = ip
        self.customer = customer = custdict[vid]
        self.gw = dictentry.get('gw', None)
        customer.ipv6.append(self)

    def __repr__(self):
        return '<%s ip=%s gw=%r>' % (self.__class__.__name__, self.ip, self.gw)

##############################################################################

def setup(toolname):
    argp = argparse.ArgumentParser(description = toolname)
    argp.add_argument('--spec', type = str)
    return argp

def load(argp, specdeffd = lambda: sys.stdin):
    global args

    args = argp.parse_args()

    if args.spec is not None:
        specfd = open(args.spec, 'r')
    else:
        specfd = specdeffd()
    spec = json.load(specfd)

    for k, v in sorted(spec['classes'].items()):
        customers.append(Customer(k, v))

    for net, data in sorted(spec['subnets'].items()):
        if ':' in net:
            Subnet6(net, data)
        else:
            Subnet4(net, data)

    return (spec, args)

if __name__ == '__main__':
    sys.stderr.write('this is a module.\n')
