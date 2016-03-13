#!/bin/sh

set -e

. "`dirname $0`"/../settings

# This script runs in the private/nat router netns

if [ -r "/run/dhcpd-private.pid" ]; then
	kill -TERM $(cat /run/dhcpd-private.pid) || true
fi
