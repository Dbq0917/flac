/* test_libFLAC - Unit tester for libFLAC
 * Copyright (C) 2000-2009  Josh Coalson
 * Copyright (C) 2011-2025  Xiph.Org Foundation
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifdef HAVE_CONFIG_H
#  include <config.h>
#endif

#include "FLAC/assert.h"
#include "share/compat.h"
#include "private/bitreader.h" /* from the libFLAC private include area */
#include "bitreader.h"
#include <stdio.h>
#include <string.h> /* for memcpy() */

/*
 * WATCHOUT!  Since FLAC__BitReader is a private structure, we use a copy of
 * the definition here to get at the internals.  Make sure this is kept up
 * to date with what is in ../libFLAC/bitreader.c
 */
#if (ENABLE_64_BIT_WORDS == 0)

typedef FLAC__uint32 brword;
#define FLAC__BYTES_PER_WORD 4
#define FLAC__BITS_PER_WORD 32

#else

typedef FLAC__uint64 brword;
#define FLAC__BYTES_PER_WORD 8
#define FLAC__BITS_PER_WORD 64

#endif

struct FLAC__BitReader {
	/* any partially-consumed word at the head will stay right-justified as bits are consumed from the left */
	/* any incomplete word at the tail will be left-justified, and bytes from the read callback are added on the right */
	brword *buffer;
	uint32_t capacity; /* in words */
	uint32_t words; /* # of completed words in buffer */
	uint32_t bytes; /* # of bytes in incomplete word at buffer[words] */
	uint32_t consumed_words; /* #words ... */
	uint32_t consumed_bits; /* ... + (#bits of head word) already consumed from the front of buffer */
	uint32_t read_crc16; /* the running frame CRC */
	uint32_t crc16_offset; /* the number of words in the current buffer that should not be CRC'd */
	uint32_t crc16_align; /* the number of bits in the current consumed word that should not be CRC'd */
	FLAC__bool read_limit_set; /* whether reads are limited */
	uint32_t read_limit; /* the remaining size of what can be read */
	uint32_t last_seen_framesync; /* the location of the last seen framesync, if it is in the buffer, in bits from front of buffer */
	FLAC__BitReaderReadCallback read_callback;
	void *client_data;
};

static FLAC__bool read_callback(FLAC__byte buffer[], size_t *bytes, void *data);
static FLAC__bool rice_read_callback(FLAC__byte buffer[], size_t *bytes, void *data);
static FLAC__bool test_rice_limits_(void);

static void FLAC__bitreader_dump(const FLAC__BitReader *br, FILE *out)
{
	uint32_t i, j;
	if(br == 0) {
		fprintf(out, "bitreader is NULL\n");
	}
	else {
		fprintf(out, "bitreader: capacity=%u words=%u bytes=%u consumed: words=%u, bits=%u\n", br->capacity, br->words, br->bytes, br->consumed_words, br->consumed_bits);

		for(i = 0; i < br->words; i++) {
			fprintf(out, "%08X: ", i);
			for(j = 0; j < FLAC__BITS_PER_WORD; j++)
				if(i < br->consumed_words || (i == br->consumed_words && j < br->consumed_bits))
					fprintf(out, ".");
				else
					fprintf(out, "%01d", br->buffer[i] & ((brword)1 << (FLAC__BITS_PER_WORD-j-1)) ? 1:0);
			fprintf(out, "\n");
		}
		if(br->bytes > 0) {
			fprintf(out, "%08X: ", i);
			for(j = 0; j < br->bytes*8; j++)
				if(i < br->consumed_words || (i == br->consumed_words && j < br->consumed_bits))
					fprintf(out, ".");
				else
					fprintf(out, "%01d", br->buffer[i] & ((brword)1 << (br->bytes*8-j-1)) ? 1:0);
			fprintf(out, "\n");
		}
	}
}

FLAC__bool test_bitreader(void)
{
	FLAC__BitReader *br;
	FLAC__bool ok;
	uint32_t i;
	uint32_t words, bits; /* what we think br->consumed_words and br->consumed_bits should be */

	FLAC__uint16	 crc,expected_crcs[4] = { 0x5e4c, 0x7f6b, 0x2272, 0x42bf };
	FLAC__byte	 data[32];

	FLAC__uint32	 val_uint32;
	FLAC__uint64	 val_uint64;

	for (i = 0; i < 32; i++)
		data[i] = i * 8 + 7;

	printf("\n+++ libFLAC unit test: bitreader\n\n");

	/*
	 * test new -> delete
	 */
	printf("testing new... ");
	br = FLAC__bitreader_new();
	if(0 == br) {
		printf("FAILED, returned NULL\n");
		return false;
	}
	printf("OK\n");

	printf("testing delete... ");
	FLAC__bitreader_delete(br);
	printf("OK\n");

	/*
	 * test new -> init -> delete
	 */
	printf("testing new... ");
	br = FLAC__bitreader_new();
	if(0 == br) {
		printf("FAILED, returned NULL\n");
		return false;
	}
	printf("OK\n");

	printf("testing init... ");
	if(!FLAC__bitreader_init(br, read_callback, data)) {
		printf("FAILED, returned false\n");
		return false;
	}
	printf("OK\n");

	printf("testing delete... ");
	FLAC__bitreader_delete(br);
	printf("OK\n");

	/*
	 * test new -> init -> clear -> delete
	 */
	printf("testing new... ");
	br = FLAC__bitreader_new();
	if(0 == br) {
		printf("FAILED, returned NULL\n");
		return false;
	}
	printf("OK\n");

	printf("testing init... ");
	if(!FLAC__bitreader_init(br, read_callback, data)) {
		printf("FAILED, returned false\n");
		return false;
	}
	printf("OK\n");

	printf("testing clear... ");
	if(!FLAC__bitreader_clear(br)) {
		printf("FAILED, returned false\n");
		return false;
	}
	printf("OK\n");

	printf("testing delete... ");
	FLAC__bitreader_delete(br);
	printf("OK\n");

	/*
	 * test normal usage
	 */
	printf("testing new... ");
	br = FLAC__bitreader_new();
	if(0 == br) {
		printf("FAILED, returned NULL\n");
		return false;
	}
	printf("OK\n");

	printf("testing init... ");
	if(!FLAC__bitreader_init(br, read_callback, data)) {
		printf("FAILED, returned false\n");
		return false;
	}
	printf("OK\n");

	printf("testing clear... ");
	if(!FLAC__bitreader_clear(br)) {
		printf("FAILED, returned false\n");
		return false;
	}
	printf("OK\n");

	words = bits = 0;

	printf("capacity = %u\n", br->capacity);

	printf("testing raw reads... ");
	ok =
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 1) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 2) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 5) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 8) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 10) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 4) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 32) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 4) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 2) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 8) &&
		FLAC__bitreader_read_raw_uint64(br, &val_uint64, 64) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 12)
	;
	if(!ok) {
		printf("FAILED\n");
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	/* we read 152 bits (=19 bytes) from the bitreader */
	words = 152 / FLAC__BITS_PER_WORD;
	bits = 152 - words*FLAC__BITS_PER_WORD;

	if(br->consumed_words != words) {
		printf("FAILED word count %u != %u\n", br->consumed_words, words);
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	if(br->consumed_bits != bits) {
		printf("FAILED bit count %u != %u\n", br->consumed_bits, bits);
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	crc = FLAC__bitreader_get_read_crc16(br);
	if(crc != expected_crcs[0]) {
		printf("FAILED reported CRC 0x%04x does not match expected 0x%04x\n", crc, expected_crcs[0]);
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	printf("OK\n");
	FLAC__bitreader_dump(br, stdout);

	printf("testing CRC reset... ");
	FLAC__bitreader_clear(br);
	FLAC__bitreader_reset_read_crc16(br, 0xFFFF);
	crc = FLAC__bitreader_get_read_crc16(br);
	if(crc != 0xFFFF) {
		printf("FAILED reported CRC 0x%04x does not match expected 0xFFFF\n", crc);
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	FLAC__bitreader_reset_read_crc16(br, 0);
	crc = FLAC__bitreader_get_read_crc16(br);
	if(crc != 0) {
		printf("FAILED reported CRC 0x%04x does not match expected 0x0000\n", crc);
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	FLAC__bitreader_read_raw_uint32(br, &val_uint32, 16);
	FLAC__bitreader_reset_read_crc16(br, 0);
	FLAC__bitreader_read_raw_uint32(br, &val_uint32, 32);
	crc = FLAC__bitreader_get_read_crc16(br);
	if(crc != expected_crcs[1]) {
		printf("FAILED reported CRC 0x%04x does not match expected 0x%04x\n", crc, expected_crcs[1]);
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	printf("OK\n");

	printf("testing unaligned < 32 bit reads... ");
	FLAC__bitreader_clear(br);
	FLAC__bitreader_skip_bits_no_crc(br, 8);
	FLAC__bitreader_reset_read_crc16(br, 0);
	ok =
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 1) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 2) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 5) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 8)
	;
	if(!ok) {
		printf("FAILED\n");
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	crc = FLAC__bitreader_get_read_crc16(br);
	if(crc != expected_crcs[2]) {
		printf("FAILED reported CRC 0x%04x does not match expected 0x%04x\n", crc, expected_crcs[2]);
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	printf("OK\n");
	FLAC__bitreader_dump(br, stdout);

	printf("testing unaligned < 64 bit reads... ");
	FLAC__bitreader_clear(br);
	FLAC__bitreader_skip_bits_no_crc(br, 8);
	FLAC__bitreader_reset_read_crc16(br, 0);
	ok =
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 1) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 2) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 5) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 8) &&
		FLAC__bitreader_read_raw_uint32(br, &val_uint32, 32)
	;
	if(!ok) {
		printf("FAILED\n");
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	crc = FLAC__bitreader_get_read_crc16(br);
	if(crc != expected_crcs[3]) {
		printf("FAILED reported CRC 0x%04x does not match expected 0x%04x\n", crc, expected_crcs[3]);
		FLAC__bitreader_dump(br, stdout);
		return false;
	}
	printf("OK\n");
	FLAC__bitreader_dump(br, stdout);

	printf("testing rice unary length limits across read boundaries... ");
	if(!test_rice_limits_()) {
		printf("FAILED\n");
		return false;
	}
	printf("OK\n");

	printf("testing free... ");
	FLAC__bitreader_free(br);
	printf("OK\n");

	printf("testing delete... ");
	FLAC__bitreader_delete(br);
	printf("OK\n");

	printf("\nPASSED!\n");
	return true;
}

/*----------------------------------------------------------------------------*/

static const FLAC__byte *rice_input;
static size_t rice_input_length;
static size_t rice_input_position;
static size_t rice_read_chunk;

static FLAC__bool rice_read_callback(FLAC__byte buffer[], size_t *bytes, void *data)
{
	size_t n = *bytes;

	(void)data;
	if(rice_read_chunk > 0 && n > rice_read_chunk)
		n = rice_read_chunk;
	if(n > rice_input_length - rice_input_position)
		n = rice_input_length - rice_input_position;
	if(n == 0) {
		*bytes = 0;
		return false;
	}
	memcpy(buffer, rice_input + rice_input_position, n);
	rice_input_position += n;
	*bytes = n;
	return true;
}

static void set_bit_(FLAC__byte *buffer, size_t bit)
{
	buffer[bit / 8] |= (FLAC__byte)(0x80u >> (bit % 8));
}

static FLAC__bool read_rice_values_(const FLAC__byte *data, size_t length, size_t chunk, int *values, uint32_t count, uint32_t parameter)
{
	FLAC__BitReader *br = FLAC__bitreader_new();
	FLAC__bool ok;

	if(br == NULL)
		return false;
	rice_input = data;
	rice_input_length = length;
	rice_input_position = 0;
	rice_read_chunk = chunk;
	if(!FLAC__bitreader_init(br, rice_read_callback, NULL)) {
		FLAC__bitreader_delete(br);
		return false;
	}
	ok = FLAC__bitreader_read_rice_signed_block(br, values, count, parameter);
	FLAC__bitreader_delete(br);
	return ok;
}

static FLAC__bool test_rice_limits_(void)
{
	static const size_t chunks[] = { 0, 1, 7, 13, 64 };
	FLAC__byte overlimit[520];
	FLAC__byte valid[2] = { 0x36, 0xc0 }; /* 2 / 5 and 0 / 3 with parameter 3 */
	FLAC__byte edge[520];
	int values[2];
	uint32_t i;

	memset(overlimit, 0, sizeof(overlimit));
	set_bit_(overlimit, 4096); /* quotient 4096, one above UINT32_MAX >> 20 */
	for(i = 0; i < sizeof(chunks)/sizeof(chunks[0]); i++) {
		values[0] = 0;
		if(read_rice_values_(overlimit, sizeof(overlimit), chunks[i], values, 1, 20)) {
			printf("over-limit quotient %u accepted with chunk size %u\n", values[0], (uint32_t)chunks[i]);
			return false;
		}
	}

	/* A code that crosses a byte boundary must still compose bit-exactly. */
	for(i = 0; i < sizeof(chunks)/sizeof(chunks[0]); i++) {
		values[0] = values[1] = 0;
		if(!read_rice_values_(valid, sizeof(valid), chunks[i], values, 2, 3) || values[0] != -11 || values[1] != -2) {
			printf("valid crossing code decoded as %d,%d with chunk size %u\n", values[0], values[1], (uint32_t)chunks[i]);
			return false;
		}
	}

	/* Exactly the limit is valid; the check must reject only limit + 1. */
	memset(edge, 0, sizeof(edge));
	set_bit_(edge, 4095);
	for(i = 0; i < sizeof(chunks)/sizeof(chunks[0]); i++) {
		values[0] = 0;
		if(!read_rice_values_(edge, sizeof(edge), chunks[i], values, 1, 20) || values[0] != 2146959360) {
			printf("limit quotient decoded as %d with chunk size %u\n", values[0], (uint32_t)chunks[i]);
			return false;
		}
	}

	return true;
}

static FLAC__bool read_callback(FLAC__byte buffer[], size_t *bytes, void *data)
{
	if (*bytes > 32)
		*bytes = 32;

	memcpy(buffer, data, *bytes);

	return true;
}
