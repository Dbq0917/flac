#!/bin/sh

# Run a decoder command in a child process with a hard address-space limit.
# Usage: run_decoder_bounded.sh MEMORY_KB PROGRAM [ARGS...]
#
# This is a small reference wrapper for services that decode untrusted audio.
# Production deployments can use the same idea with cgroups, a container
# memory limit or an OS sandbox.

if [ "$#" -lt 2 ]; then
	echo "usage: $0 MEMORY_KB PROGRAM [ARGS...]" 1>&2
	exit 2
fi

limit_kb=$1
shift

ulimit -v "$limit_kb" 2>/dev/null || {
	echo "cannot apply address-space limit of ${limit_kb} KiB" 1>&2
	exit 125
}

exec "$@"
