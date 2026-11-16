import hashlib, struct, sys

def crc8(b):
    c = 0
    for x in b:
        c ^= x
        for _ in range(8):
            c = ((c << 1) ^ 0x07) & 0xff if c & 0x80 else (c << 1) & 0xff
    return c

def crc16(b):
    c = 0
    for x in b:
        c ^= x << 8
        for _ in range(8):
            c = ((c << 1) ^ 0x8005) & 0xffff if c & 0x8000 else (c << 1) & 0xffff
    return c

def build(path, zeros, k, lsbs, bps, padding, md5_of):
    n = 16
    ssc = {16: 4, 32: 7}[bps]
    folded_wrapped = ((zeros << k) | lsbs) & 0xffffffff
    wrapped = (folded_wrapped >> 1) ^ -(folded_wrapped & 1)
    pcm_vals = [wrapped] + [0] * (n - 1)
    fmt = {16: "<h", 32: "<i"}[bps]
    if md5_of == "wrapped":
        md5 = hashlib.md5(b"".join(struct.pack(fmt, v) for v in pcm_vals)).digest()
    else:
        md5 = bytes(16)
    si = struct.pack(">HH", n, n) + bytes(6)
    si += struct.pack(">Q", (44100 << 44) | ((bps - 1) << 36) | n) + md5
    out = b"fLaC" + bytes([0x00 if padding else 0x80, 0, 0, 34]) + si
    if padding:
        out += bytes([0x81]) + padding.to_bytes(3, "big") + bytes(padding)
    hdr = bytes([0xff, 0xf8, 0x69, (0 << 4) | (ssc << 1), 0x00, n - 1])
    frame = hdr + bytes([crc8(hdr)])
    bits = []
    w = lambda v, m: bits.extend((v >> s) & 1 for s in range(m - 1, -1, -1))
    w(0x10, 8)
    w(1, 2)
    w(0, 4)
    w(k, 5)
    bits.extend([0] * zeros + [1])
    w(lsbs, k)
    for _ in range(n - 1):
        bits.append(1)
        w(0, k)
    while len(bits) % 8:
        bits.append(0)
    frame += bytes(int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8))
    frame += struct.pack(">H", crc16(frame))
    data = out + frame
    open(path, "wb").write(data)
    true_folded = (zeros << k) | lsbs
    true_res = (true_folded >> 1) ^ -(true_folded & 1)
    print(f"{path}: {len(data)} bytes, zeros={zeros} k={k} lsbs={lsbs} bps={bps} padding={padding} true_residual={true_res} libflac_wrapped={wrapped} md5={md5_of}")

a = sys.argv
build(a[1], int(a[2]), int(a[3]), int(a[4]), int(a[5]), int(a[6]), a[7])
