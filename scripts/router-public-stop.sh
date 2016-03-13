#!/bin/sh

set -e

. "`dirname $0`"/../settings

# This script runs in the public router netns

if [ -r "/run/runsvdir-public.pid" ]; then
	kill -HUP $(cat /run/runsvdir-public.pid) || true
fi
