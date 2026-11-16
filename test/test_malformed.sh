#!/bin/sh -e

#  FLAC - Free Lossless Audio Codec
#  Copyright (C) 2001-2009  Josh Coalson
#  Copyright (C) 2011-2025  Xiph.Org Foundation
#
#  This file is part the FLAC project.  FLAC is comprised of several
#  components distributed under different licenses.  The codec libraries
#  are distributed under Xiph.Org's BSD-like license (see the file
#  COPYING.Xiph in this distribution).  All other programs, libraries, and
#  plugins are distributed under the LGPL or GPL (see COPYING.LGPL and
#  COPYING.GPL).  The documentation is distributed under the terms of the
#  GNU FDL (see COPYING.FDL).  Each file in the FLAC distribution contains
#  at the top the terms under which it has been distributed.

. ./common.sh

trap 'rm -f malformed.out' EXIT

PATH="$(pwd)/../src/flac:$PATH"
PATH="$(pwd)/../src/test_grabbag/cuesheet:$PATH"
PATH="$(pwd)/../objs/$BUILD/bin:$PATH"

flac${EXE} --help >/dev/null 2>&1 || die "ERROR can't find flac executable"

memory_limit=${FLAC__TEST_MEMORY_LIMIT:-262144}
use_memory_limit=no
if "$top_srcdir/test/security-regression/run_decoder_bounded.sh" "$memory_limit" flac${EXE} --help >/dev/null 2>&1; then
	use_memory_limit=yes
fi

run_flac ()
{
	if [ "$use_memory_limit" = yes ]; then
		"$top_srcdir/test/security-regression/run_decoder_bounded.sh" "$memory_limit" flac${EXE} "$@"
	else
		flac${EXE} "$@"
	fi
}

for input in "$top_srcdir"/test/security-regression/*.flac; do
	echo "testing malformed stream $(basename "$input")..."
	if run_flac --silent -t "$input" >malformed.out 2>&1; then
		cat malformed.out
		die "ERROR: malformed stream was accepted"
	fi
	grep -q 'at offset [0-9][0-9]* bytes' malformed.out || {
		cat malformed.out
		die "ERROR: decode failure did not report an offset"
	}
done

if command -v test_cuesheet >/dev/null 2>&1; then
	echo "testing cuesheet with too many indices..."
	if test_cuesheet "$top_srcdir/test/security-regression/cuesheet-256-indices.cue" 1000000 48000 >malformed.out 2>&1; then
		cat malformed.out
		die "ERROR: cuesheet with more than 255 indices was accepted"
	fi
fi

echo "malformed decoder tests passed"
