# Decoder security regression samples

These files are intentionally malformed FLAC streams used to keep decoder
bounds checks regression-tested:

* `rice-unary-limit-tail.flac`
* `rice-unary-limit-padding-6900.flac`
* `rice-unary-limit-padding-7628.flac`
* `cuesheet-256-indices.cue`

The three FLAC files contain a Rice code with parameter 20 and a quotient of 4096,
which is one above the largest quotient allowed for a 32-bit residual.
The padding variants place the same frame at different buffer refill
positions.  They must all be rejected with `LOST_SYNC`, independent of
how the input is split into reads.

The cue sheet has one track with 256 index points.  The FLAC cue sheet
format stores the index count in eight bits, so parsing it must fail
instead of truncating the count and writing out of bounds.

`generate_rice_unary_limit.py` regenerates the samples.  It is kept so new
variants (different parameters, padding, bit depths and sizes) can be
produced without relying on the original fuzzing artifact.

`run_decoder_bounded.sh` is a reference wrapper that puts the decoder in a
child process with a hard address-space limit.  `test_malformed.sh` uses it
when the platform and build support `ulimit -v` (sanitizer builds reserve too
much virtual address space for this check and fall back to an unlimited
child).
