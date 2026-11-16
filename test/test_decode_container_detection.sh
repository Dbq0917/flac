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
PATH="$(pwd)/../src/metaflac:$PATH"
PATH="$(pwd)/../src/test_streams:$PATH"
PATH="$(pwd)/../objs/$BUILD/bin:$PATH"

flac${EXE} --help 1>/dev/null 2>/dev/null || die "ERROR can't find flac executable"
metaflac${EXE} --help 1>/dev/null 2>/dev/null || die "ERROR can't find metaflac executable"

if [ ! -f noise.raw ] ; then
	test_streams${EXE} || die "ERROR during test_streams"
fi

#
# This test verifies the archive-ingest requirements for decoding:
#  - FLAC and Ogg FLAC streams are detected from the file contents, never
#    from the file name extension, so both kinds can be mixed in one
#    directory with arbitrary names
#  - sample rate, bits per sample, channel count and channel order of the
#    decoded output match the stream declaration exactly (no resampling,
#    no re-layout), which is checked by demanding bit-exact output
#  - an unsupported format is reported differently from a damaged stream
#  - a truncated stream yields the samples decoded so far plus a warning
#    instead of failing outright
#  - a decode log is written for traceability
#

raw_to_flac() # $1=channels $2=bps $3=rate $4=in.raw $5=out.flac [$6=--ogg]
	flac${EXE} -s -f $6 --force-raw-format --endian=little --sign=signed \
		--channels=$1 --bps=$2 --sample-rate=$3 -o "$5" "$4" || die "ERROR encoding $5"

decode_to_raw() # $1=in $2=out.raw
	flac${EXE} -s -f -d --force-raw-format --endian=little --sign=signed -o "$2" "$1" || die "ERROR decoding $1"

echo "Generating source material..."
# frame-aligned chunks of noise.raw: distinct content per channel position,
# so any channel reordering, resampling or bit-depth change breaks the
# bit-exact comparisons below
dd if=noise.raw of=src-6ch-24bit-96k.raw bs=18 count=12000 2>/dev/null || die "ERROR making 6ch source"
dd if=noise.raw of=src-2ch-16bit-44k.raw bs=4 count=11025 2>/dev/null || die "ERROR making 2ch source"
dd if=noise.raw of=src-8ch-16bit-48k.raw bs=16 count=48000 2>/dev/null || die "ERROR making 8ch source"
dd if=noise.raw of=src-1ch-16bit-22k.raw bs=2 count=11025 2>/dev/null || die "ERROR making 1ch source"

echo "Encoding native FLAC and Ogg FLAC streams with misleading names..."
raw_to_flac 6 24 96000 src-6ch-24bit-96k.raw native.flac
raw_to_flac 2 16 44100 src-2ch-16bit-44k.raw ogg-named.flac --ogg
raw_to_flac 8 16 48000 src-8ch-16bit-48k.raw ogg-no-extension --ogg
raw_to_flac 8 16 48000 src-8ch-16bit-48k.raw ogg-named.oga --ogg
raw_to_flac 1 16 22050 src-1ch-16bit-22k.raw native-named.oga

echo "Testing content-based container detection and bit-exact decoding..."
decode_to_raw native.flac dec-native.raw
cmp src-6ch-24bit-96k.raw dec-native.raw || die "ERROR: native FLAC decode is not bit-exact"
decode_to_raw ogg-named.flac dec-ogg-named-flac.raw
cmp src-2ch-16bit-44k.raw dec-ogg-named-flac.raw || die "ERROR: Ogg FLAC (named .flac) decode is not bit-exact"
decode_to_raw ogg-no-extension dec-ogg-noext.raw
cmp src-8ch-16bit-48k.raw dec-ogg-noext.raw || die "ERROR: Ogg FLAC (no extension) decode is not bit-exact"
decode_to_raw ogg-named.oga dec-ogg-oga.raw
cmp src-8ch-16bit-48k.raw dec-ogg-oga.raw || die "ERROR: Ogg FLAC (named .oga) decode is not bit-exact"
decode_to_raw native-named.oga dec-native-oga.raw
cmp src-1ch-16bit-22k.raw dec-native-oga.raw || die "ERROR: native FLAC (named .oga) decode is not bit-exact"

echo "Testing that decoded parameters match the stream declaration..."
rate=`metaflac${EXE} --show-sample-rate native.flac`
channels=`metaflac${EXE} --show-channels native.flac`
bps=`metaflac${EXE} --show-bps native.flac`
[ "$rate" = 96000 ] || die "ERROR: sample rate $rate != 96000"
[ "$channels" = 6 ] || die "ERROR: channels $channels != 6"
[ "$bps" = 24 ] || die "ERROR: bps $bps != 24"

# the decoded WAVE header must carry the declared parameters for both containers
check_wave_header() # $1=wav $2=channels $3=rate $4=bps
{
	val=`dd if="$1" bs=1 skip=22 count=2 2>/dev/null | od -An -tu1 | tr -s ' ' '\n' | grep -v '^$' | head -1`
	[ "$val" = "$2" ] || die "ERROR: $1 WAVE header channels $val != $2"
	val=`dd if="$1" bs=1 skip=24 count=4 2>/dev/null | od -An -tu4 | tr -d ' '`
	[ "$val" = "$3" ] || die "ERROR: $1 WAVE header sample rate $val != $3"
	val=`dd if="$1" bs=1 skip=34 count=2 2>/dev/null | od -An -tu2 | tr -d ' '`
	[ "$val" = "$4" ] || die "ERROR: $1 WAVE header bits-per-sample $val != $4"
}
flac${EXE} -s -f -d -o dec-6ch.wav native.flac || die "ERROR decoding native.flac to WAVE"
check_wave_header dec-6ch.wav 6 96000 24
flac${EXE} -s -f -d -o dec-2ch.wav ogg-named.flac || die "ERROR decoding ogg-named.flac to WAVE"
check_wave_header dec-2ch.wav 2 44100 16
flac${EXE} -s -f -d -o dec-8ch.wav ogg-no-extension || die "ERROR decoding ogg-no-extension to WAVE"
check_wave_header dec-8ch.wav 8 48000 16

echo "Testing direct decode against the transcode chain (no extra loss allowed)..."
# transcode chain: Ogg FLAC -> WAVE -> native FLAC -> raw
flac${EXE} -s -f -d -o transcode.wav ogg-no-extension || die "ERROR: transcode step 1 failed"
flac${EXE} -s -f -o transcode.flac transcode.wav || die "ERROR: transcode step 2 failed"
decode_to_raw transcode.flac transcode.raw
cmp src-8ch-16bit-48k.raw transcode.raw || die "ERROR: transcode chain is not lossless"
cmp dec-ogg-noext.raw transcode.raw || die "ERROR: direct decode differs from transcode chain"

echo "Testing mixed-directory batch decode of both containers..."
mkdir -p mixed-dir
cp native.flac mixed-dir/item-0001.bin
cp ogg-named.flac mixed-dir/item-0002.bin
cp ogg-no-extension mixed-dir/item-0003.bin
cp native-named.oga mixed-dir/item-0004.bin
(
	cd mixed-dir &&
	for f in item-0001.bin item-0002.bin item-0003.bin item-0004.bin ; do
		flac${EXE} -s -f -t "$f" 2>/dev/null || exit 1
	done
) || die "ERROR: mixed-directory batch test failed"

echo "Testing unsupported format is distinguished from a damaged stream..."
echo "this is not an audio stream at all" > not-audio.flac
if flac${EXE} -s -f -d -o not-audio.wav not-audio.flac 2>not-audio.err ; then
	die "ERROR: unsupported input was decoded but should have been rejected"
else
	status=$?
fi
[ "$status" -lt 128 ] || die "ERROR: flac terminated by a signal (status $status)"
grep -Fq "unsupported file format" not-audio.err || die "ERROR: unsupported input not reported as such"
[ ! -f not-audio.wav ] || die "ERROR: unsupported input produced output"

cp native.flac corrupt.flac
printf '\336\255\276\357\336\255\276\357' | dd of=corrupt.flac bs=1 seek=100000 conv=notrunc 2>/dev/null || die "ERROR making corrupt stream"
if flac${EXE} -s -f -d -o corrupt.wav corrupt.flac 2>corrupt.err ; then
	die "ERROR: corrupt stream was decoded without complaint"
else
	status=$?
fi
[ "$status" -lt 128 ] || die "ERROR: flac terminated by a signal (status $status)"
grep -Fq "ERROR" corrupt.err || die "ERROR: corrupt stream did not report an error"
if grep -Fq "unsupported file format" corrupt.err ; then
	die "ERROR: corrupt stream was misreported as an unsupported format"
fi
[ ! -f corrupt.wav ] || die "ERROR: corrupt stream produced output"

echo "Testing truncated streams yield partial output plus a warning..."
size=`wc -c < native.flac`
head -c $((size * 3 / 5 + 1)) native.flac > truncated.flac
flac${EXE} -s -f -d --force-raw-format --endian=little --sign=signed -o truncated.raw truncated.flac 2>truncated.err ||
	die "ERROR: truncated stream failed outright instead of delivering partial output"
grep -Fq "WARNING, input file is truncated" truncated.err || die "ERROR: truncation was not warned about"
[ -f truncated.raw ] || die "ERROR: truncated stream produced no partial output"
partial_size=`wc -c < truncated.raw`
[ "$partial_size" -gt 0 ] || die "ERROR: partial output is empty"
[ "$partial_size" -lt `wc -c < src-6ch-24bit-96k.raw` ] || die "ERROR: partial output is not partial"
head -c "$partial_size" src-6ch-24bit-96k.raw > truncated-expected.raw
cmp truncated-expected.raw truncated.raw || die "ERROR: partial output does not match the source prefix"
# truncated output must carry consistent headers when decoding to WAVE
flac${EXE} -s -f -d -o truncated.wav truncated.flac 2>/dev/null || die "ERROR: truncated stream to WAVE failed"
# flac writes WAVE_FORMAT_EXTENSIBLE for 6ch/24bit, so the data chunk size sits at offset 64
data_size=`dd if=truncated.wav bs=1 skip=64 count=4 2>/dev/null | od -An -tu4 | tr -d ' '`
[ "$data_size" = "$partial_size" ] || die "ERROR: WAVE data size $data_size != actual $partial_size"
# testing mode must also warn, not fail
flac${EXE} -s -t truncated.flac 2>truncated-test.err || die "ERROR: flac -t failed on truncated stream"
grep -Fq "WARNING, input file is truncated" truncated-test.err || die "ERROR: flac -t did not warn about truncation"
# same for a truncated Ogg FLAC stream
size=`wc -c < ogg-no-extension`
head -c $((size * 9 / 10 + 1)) ogg-no-extension > truncated.oga
flac${EXE} -s -f -d --force-raw-format --endian=little --sign=signed -o truncated-ogg.raw truncated.oga 2>truncated-ogg.err ||
	die "ERROR: truncated Ogg FLAC stream failed outright"
grep -Fq "WARNING, input file is truncated" truncated-ogg.err || die "ERROR: Ogg truncation was not warned about"
partial_size=`wc -c < truncated-ogg.raw`
head -c "$partial_size" src-8ch-16bit-48k.raw > truncated-ogg-expected.raw
cmp truncated-ogg-expected.raw truncated-ogg.raw || die "ERROR: partial Ogg output does not match the source prefix"

echo "Testing the decode log..."
logfile=decode.log
> "$logfile"
flac${EXE} -s -f -d --decode-log="$logfile" -o log-out-1.wav native.flac 2>/dev/null || die "ERROR: logged decode failed"
flac${EXE} -s -f -d --decode-log="$logfile" -o log-out-2.wav ogg-named.flac 2>/dev/null || die "ERROR: logged decode failed"
flac${EXE} -s -f -d --decode-log="$logfile" -o log-out-3.wav truncated.flac 2>/dev/null || die "ERROR: logged truncated decode failed"
if flac${EXE} -s -f -d --decode-log="$logfile" -o log-out-4.wav not-audio.flac 2>/dev/null ; then
	die "ERROR: unsupported input was decoded"
fi
if flac${EXE} -s -f -d --decode-log="$logfile" -o log-out-5.wav corrupt.flac 2>/dev/null ; then
	die "ERROR: corrupt stream was decoded"
fi
grep -Fq "file=native.flac" "$logfile" || die "ERROR: log misses native.flac entry"
grep -Fq "container=flac sample_rate=96000 channels=6 bits_per_sample=24 total_samples=12000 decoded_samples=12000 md5=ok status=ok" "$logfile" ||
	die "ERROR: log entry for native.flac is wrong"
grep -Fq "container=ogg-flac sample_rate=44100 channels=2 bits_per_sample=16" "$logfile" ||
	die "ERROR: log entry for ogg-named.flac is wrong"
grep -Fq "status=truncated" "$logfile" || die "ERROR: log misses truncated entry"
grep -Fq 'status=failed detail="unsupported file format"' "$logfile" || die "ERROR: log misses unsupported-format entry"
[ "`grep -c 'status=failed' "$logfile"`" -eq 2 ] || die "ERROR: log should record exactly two failures"

echo "OK"
