#!/bin/sh

set -e

. "`dirname $0`"/../settings

# This script runs in the private/nat router netns

if [ -r "/run/dhcpd-private.pid" ]; then
	kill -TERM $(cat /run/dhcpd-private.pid) || true
fi

if [ -r "/run/runsvdir-private.pid" ]; then
	kill -HUP $(cat /run/runsvdir-private.pid) || true
fi
