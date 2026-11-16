#!/bin/sh -e

#  FLAC - Free Lossless Audio Codec
#  Copyright (C) 2001-2009  Josh Coalson
#  Copyright (C) 2011-2025  Xiph.Org Foundation
#
#  This file is part the FLAC project.  FLAC is comprised of several
#  components distributed under different licenses.  The codec libraries
#  are distributed under Xiph.Org's BSD-like license (see the file
#  COPYING.Xiph in this distribution).  All other programs, libraries, and
#  plugins are distributed under the GPL (see COPYING.GPL).  The documentation
#  is distributed under the Gnu FDL (see COPYING.FDL).  Each file in the
#  FLAC distribution contains at the top the terms under which it may be
#  distributed.
#
#  Since this particular file is relevant to all components of FLAC,
#  it may be distributed under the Xiph.Org license, which is the least
#  restrictive of those mentioned above.  See the file COPYING.Xiph in this
#  distribution.

. ./common.sh

PATH="$(pwd)/../src/flac:$PATH"
PATH="$(pwd)/../src/test_streams:$PATH"
PATH="$(pwd)/../objs/$BUILD/bin:$PATH"

flac${EXE} --help 1>/dev/null 2>/dev/null || die "ERROR can't find flac executable"

if [ ! -f bad-wav-bps-4.wav ] ; then
	test_streams${EXE} || die "ERROR during test_streams"
fi

bad_bps_cases="
0:0
4:4
5:5
6:6
7:7
9:9
12:12
20:20
33:33
65535:32
"

check_rejected()
{
	filename="$1"
	expected="$2"

	if flac${EXE} -s -f -o "rejected-${filename}.flac" "$filename" 2>"rejected.err" ; then
		die "ERROR: $filename was accepted but should have been rejected"
	else
		status=$?
	fi
	[ "$status" -lt 128 ] || die "ERROR: $filename terminated by a signal (status $status)"
	grep -Fq "$expected" "rejected.err" || die "ERROR: $filename did not report: $expected"
}

echo "Testing rejection of malformed WAV header fields..."
for entry in $bad_bps_cases ; do
	bps=${entry%%:*}
	check_rejected "bad-wav-bps-${bps}.wav" "invalid WAVE bits-per-sample ${bps}: must be 8, 16, 24, or 32"
done
check_rejected bad-wav-valid-0.wav "invalid WAVE valid bits-per-sample 0: must be between 4 and 32"
check_rejected bad-wav-valid-3.wav "invalid WAVE valid bits-per-sample 3: must be between 4 and 32"
check_rejected bad-wav-valid-33.wav "wValidBitsPerSample (33) > wBitsPerSample (16)"
check_rejected bad-wav-channels-0.wav "invalid WAVE number of channels 0: must be between 1 and 8"
check_rejected bad-wav-channels-9.wav "invalid WAVE number of channels 9: must be between 1 and 8"

echo "Testing batch behavior, failed-file listing and anomaly counts..."
workdir=wav-header-validation
rm -rf "$workdir"
mkdir -p "$workdir/single" "$workdir/batch"

good_files="rt-2-16-4777.wav rt-2-24-4777.wav rt-4-16-4777.wav rt-8-16-111.wav"
bad_files="bad-wav-bps-4.wav bad-wav-bps-4-copy.wav bad-wav-bps-5.wav bad-wav-bps-65535.wav bad-wav-valid-0.wav"

for filename in $good_files ; do
	cp "$filename" "$workdir/single/"
	cp "$filename" "$workdir/batch/"
done
for filename in $bad_files ; do
	case "$filename" in
		bad-wav-bps-4-copy.wav) source_file=bad-wav-bps-4.wav ;;
		*) source_file=$filename ;;
	esac
	cp "$source_file" "$workdir/batch/$filename"
done

(
	cd "$workdir/single" &&
	flac${EXE} -s -f $good_files
) || die "ERROR: failed to encode the reference batch"

if (
	cd "$workdir/batch" &&
	flac${EXE} -s -f \
		bad-wav-bps-4.wav rt-2-16-4777.wav \
		bad-wav-bps-4-copy.wav rt-2-24-4777.wav \
		bad-wav-bps-5.wav rt-4-16-4777.wav \
		bad-wav-bps-65535.wav rt-8-16-111.wav \
		bad-wav-valid-0.wav
) 2>"$workdir/batch.err" ; then
	die "ERROR: the batch should have reported at least one failure"
else
	batch_status=$?
fi
[ "$batch_status" -lt 128 ] || die "ERROR: batch terminated by a signal (status $batch_status)"

for filename in $good_files ; do
	outname=${filename%.wav}.flac
	[ -f "$workdir/batch/$outname" ] || die "ERROR: batch did not finish $filename"
	cmp "$workdir/single/$outname" "$workdir/batch/$outname" || die "ERROR: batch output for $filename differs"
done
for filename in bad-wav-bps-4.wav bad-wav-bps-4-copy.wav bad-wav-bps-5.wav bad-wav-bps-65535.wav bad-wav-valid-0.wav ; do
	[ ! -f "$workdir/batch/${filename%.wav}.flac" ] || die "ERROR: $filename produced output"
	grep -Fq "$filename" "$workdir/batch.err" || die "ERROR: $filename missing from failure report"
done

sed -n 's/^\([^:]*\): ERROR:.*/\1/p' "$workdir/batch.err" | sort -u > "$workdir/failed-files.txt"
sed -n 's/.*invalid WAVE bits-per-sample \([0-9][0-9]*\):.*/bits-per-sample=\1/p' "$workdir/batch.err" | sort | uniq -c > "$workdir/anomaly-counts.txt"
sed -n 's/.*invalid WAVE valid bits-per-sample \([0-9][0-9]*\):.*/valid-bits-per-sample=\1/p' "$workdir/batch.err" | sort | uniq -c >> "$workdir/anomaly-counts.txt"

[ "$(wc -l < "$workdir/failed-files.txt")" -eq 5 ] || die "ERROR: failed-file list is incomplete"
grep -q 'bits-per-sample=4$' "$workdir/anomaly-counts.txt" || die "ERROR: missing anomaly count for bits-per-sample=4"
grep -q '2 bits-per-sample=4$' "$workdir/anomaly-counts.txt" || die "ERROR: wrong anomaly count for bits-per-sample=4"
grep -q '1 bits-per-sample=65535$' "$workdir/anomaly-counts.txt" || die "ERROR: missing anomaly count for bits-per-sample=65535"
grep -q '1 valid-bits-per-sample=0$' "$workdir/anomaly-counts.txt" || die "ERROR: missing anomaly count for valid-bits-per-sample=0"

echo "OK"
