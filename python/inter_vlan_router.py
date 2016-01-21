#!/usr/bin/env python

import errno
import os
import subprocess
import sys

import westspec

##############################################

def check_call(*args, **kwargs):
    command = ' '.join(args[0]) if type(args[0]) is list else args[0]
    if not dry_run:
        sys.stderr.write('%s\n' % command)
        return subprocess.check_call(*args, **kwargs)
    else:
        sys.stderr.write('\x1b[32m%s\x1b[39m\n' % command)
        return 0

class IntervlanRouter(object):
    """Manage a network namespace that performs the tasks of an
       inter-vlan router. Won't have any effect on
       system configuration until configure() is called.

       Supposed to run in the network namespace intended."""

    def __init__(self, base_if, public):
        self.base_if = base_if
        if public:
            self.customers = [c for c in westspec.customers if c.proxyif or c.extranets]
        else:
            self.customers = [c for c in westspec.customers if c.privnet is not None]
        self.public = public # Public Router or RFC1918 router?

    # Helper functions
    def iface(self, vid):
        return '%s.%d' % (self.base_if, vid)

    def vid(self, iface):
        return int(iface.split('.')[-1])

    def iproute_family(self, family):
        if family == 'ipv4':
            return '-4'
        elif family == 'ipv6':
            return '-6'
        raise Exception("Unknown family %s" % family)

    def get_addresses(self, iface, family):
        if iface not in self.get_interfaces() and dry_run:
            return []

        f = self.iproute_family(family)
        output = subprocess.check_output(['ip', '-o', f, 'addr', 'list', 'dev', iface])
        return [line.split()[3] for line in output.splitlines()]

    def get_interfaces(self):
        is_vlan = lambda name: name.startswith(self.base_if + '.')
        return [iface for iface in os.listdir('/sys/class/net') if is_vlan(iface)]

    def get_routes(self, iface, family):
        if iface not in self.get_interfaces() and dry_run:
            return []

        f = self.iproute_family(family)
        output = subprocess.check_output(['ip', '-o', f, 'route', 'list', 'dev', iface])
        rv = []
        for r in output.splitlines():
            if ' proto kernel ' in r:
                continue
            r = r.replace(' scope link ', '')
            r = r.replace(' metric 1024 ', '')
            r = r.strip()
            if r == '':
                continue
            rv.append(r)
        return rv

    def set_file(self, path, new_value):
        try:
            with open(path, 'r') as current:
                current_value = current.read().strip()
        except IOError, e:
            if e.errno == errno.ENOENT and dry_run:
                current_value = ''
            else:
                raise

        if current_value != new_value:
            check_call('echo %s > %s' % (new_value, path), shell=True)

    # Configuration Application functions
    def configure_vlans(self):
        """Add/Delete vlan interfaces"""
        current_interfaces = set(self.get_interfaces())
        new_interfaces = set([self.iface(c.vid) for c in self.customers])

        for iface in current_interfaces - new_interfaces:
            check_call(['ip', 'link', 'del', iface])
        for iface in new_interfaces - current_interfaces:
            check_call(['ip', 'link', 'add', 'link', self.base_if, iface,
                        'type', 'vlan', 'id', str(self.vid(iface))])
            check_call(['ip', 'link', 'set', iface, 'up'])

        for iface in new_interfaces:
            self.set_file('/proc/sys/net/ipv4/conf/%s/rp_filter' % iface, '1')

    def configure_ipv4_addresses(self):
        """Add/Delete ipv4 addresses"""
        for c in self.customers:
            iface = self.iface(c.vid)
            subnets = []
            if self.public:
                subnets += c.extranets
            elif c.privnet is not None:
                subnets.append(c.privnet)

            current_ips = set(self.get_addresses(iface, 'ipv4'))
            new_ips = set()
            for s in subnets:
                if s.hasrtrip('cluster'):
                    new_ips.add('%s/%d' % (s.rtrip['cluster'], s.masklen))

            for ip in current_ips - new_ips:
                check_call(['ip', 'addr', 'del', ip, 'dev', iface])
            for ip in new_ips - current_ips:
                check_call(['ip', 'addr', 'add', ip, 'dev', iface])

    def configure_ipv4_routes(self):
        """Add/Delete ipv4 routes"""
        for c in self.customers:
            iface = self.iface(c.vid)
            current_routes = set(self.get_routes(iface, 'ipv4'))

            new_routes = set()
            if self.public:
                for pi in c.proxyips:
                    r = str(pi.ip).replace('/32', '')
                    new_routes.add(r)
                for en in c.extranets:
                    if en.anyrtrip():
                        continue
                    r = str(en.ip)
                    if en.gw is not None:
                        r += ' via %s' % (en.gw)
                    new_routes.add(r)
            else:
                # We don't install any routes for private addresses, currently
                pass

            for route in sorted(current_routes - new_routes):
                cmd = ['ip', '-4', 'route', 'del', 'dev', iface]
                cmd.extend(route.split(' '))
                check_call(cmd)

            for route in sorted(new_routes - current_routes):
                cmd = ['ip', '-4', 'route', 'add', 'dev', iface]
                cmd.extend(route.split(' '))
                check_call(cmd)

    def configure_ipv4_proxyarp(self):
        """Enable/Disable per IF proxyarp towards customers
           and configure arptables accordingly."""
        filename = '/tmp/router-%s-arptables.conf' % ('public' if self.public else 'private')
        try:
            with open(filename, 'r') as current_file:
                current_content = current_file.read()
        except IOError, e:
            if e.errno == errno.ENOENT:
                current_content = ''
            else:
                raise

        new_content = '*filter\n'
        new_content += ':INPUT ACCEPT\n'
        new_content += ':OUTPUT ACCEPT\n'
        new_content += ':FORWARD ACCEPT\n'

        for c in self.customers:
            iface = self.iface(c.vid)
            self.set_file('/proc/sys/net/ipv4/conf/%s/proxy_arp' % iface,
                          '1' if c.proxyif and self.public else '0')
            self.set_file('/proc/sys/net/ipv4/neigh/%s/proxy_delay' % iface, '0')
            # Proxyarp only works with arp_ignore == 0
            self.set_file('/proc/sys/net/ipv4/conf/%s/arp_ignore' % iface,
                          '0' if c.proxyif and self.public else '1')

            # Add an arptables entry that associates each customer public IP
            # with a sensible source-ip to use for arp, e.g. Fritz!boxes are
            # very particular about what they expect here and won't answer
            # arp-requests sourced from IPs they don't consider on-link
            if self.public and c.proxyips:
                for pi in c.proxyips:
                    # XXX: MAGIC
                    if pi.ip.startswith('85.239.127.'):
                        arp_source = '85.239.127.193'
                    elif pi.ip.startswith('146.0.105.'):
                        arp_source = '146.0.105.65'
                    else:
                        raise Exception("Unknown proxyarp IP range %s" % pi.ip)
                    new_content += '-A OUTPUT -j mangle -d %s --opcode 1 --mangle-ip-s %s\n' % (
                        pi.ip, arp_source)

        new_content += '\n'
        if current_content != new_content:
            if not dry_run:
                with open(filename, 'w') as new_file:
                    new_file.write(new_content)
            check_call('arptables-restore < %s' % filename, shell=True)

    def configure_ipv6_addresses(self):
        """Add/delete IPv6 addresses on the routers"""
        for c in self.customers:
            iface = self.iface(c.vid)

            current_ips = set(self.get_addresses(iface, 'ipv6'))
            if c.ipv6 and self.public:
                new_ips = set([
                    'fe80::1/64',
                    os.getenv('RTR_PUBLIC_IPV6_IF_TEMPLATE') % c.vid # XXX: MAGIC
                ])
            else:
                new_ips = set()

            for ip in current_ips - new_ips:
                check_call(['ip', 'addr', 'del', ip, 'dev', iface])
            for ip in new_ips - current_ips:
                check_call(['ip', 'addr', 'add', ip, 'dev', iface])

    def configure_ipv6_routes(self):
        """Enable/Disable IPv6 forwarding, add/delete IPv6 routes"""
        for c in self.customers:
            iface = self.iface(c.vid)

            # Enable/Disable IPv6
            self.set_file('/proc/sys/net/ipv6/conf/%s/forwarding' % iface, '1' if c.ipv6 and self.public else '0')
            self.set_file('/proc/sys/net/ipv6/conf/%s/disable_ipv6' % iface, '0' if c.ipv6 and self.public else '1')

            # Update Routes
            current_routes = set(self.get_routes(iface, 'ipv6'))
            new_routes = set()
            if self.public:
                for en in c.ipv6:
                    if en.gw is None:
                        new_routes.add(en.ip)
                    else:
                        new_routes.add('%s via %s' % (en.ip, en.gw))
            else:
                # We don't install any routes for private addresses, currently
                pass

            for route in sorted(current_routes - new_routes):
                cmd = ['ip', '-6', 'route', 'del', 'dev', iface]
                cmd.extend(route.split(' '))
                check_call(cmd)

            for route in sorted(new_routes - current_routes):
                cmd = ['ip', '-6', 'route', 'add', 'dev', iface]
                cmd.extend(route.split(' '))
                check_call(cmd)

    def configure(self):
        self.configure_vlans()

        self.configure_ipv4_addresses()
        self.configure_ipv4_routes()
        self.configure_ipv4_proxyarp()

        self.configure_ipv6_addresses()
        self.configure_ipv6_routes()

##############################################

parser = westspec.setup('Inter-VLAN router')
parser.add_argument('--apply', action='store_true')
parser.add_argument('--mode', choices=['public', 'private'], required=True,
                    help="Whether the router should route public IPv4/IPv6 or RFC1918")
parser.add_argument('--iface', required=True,
                    help="Which interface the code should create customer vlans on")

spec, args = westspec.load(parser)
dry_run = not args.apply

##############################################

IntervlanRouter(args.iface, args.mode == 'public').configure()
