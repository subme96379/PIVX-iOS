//
//  NSData+Bitcoin.m
//  BreadWallet
//
//  Created by Aaron Voisine on 10/9/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "NSData+Bitcoin.h"
#import <CommonCrypto/CommonCrypto.h>

// bitwise left rotation
#define rotl(a, b) (((a) << (b)) | ((a) >> (32 - (b))))

// basic hash functions
#define f(x, y, z) ((x) ^ (y) ^ (z))
#define g(x, y, z) (((x) & (y)) | (~(x) & (z)))
#define h(x, y, z) (((x) | ~(y)) ^ (z))
#define i(x, y, z) (((x) & (z)) | ((y) & ~(z)))
#define j(x, y, z) ((x) ^ ((y) | ~(z)))
#define k(x, y, z) (((x) & (y)) | ((x) & (z)) | ((y) & (z)))

// basic sha1 operation
#define sha1(x, y, z) (t = rotl(a, 5) + (x) + e + (y) + (z), e = d, d = c, c = rotl(b, 30), b = a, a = t)

static void SHA1Compress(unsigned *r, unsigned *x)
{
    unsigned a = r[0], b = r[1], c = r[2], d = r[3], e = r[4], i = 0, t;
    
    while (i < 16) sha1(g(b, c, d), 0x5a827999u, x[i]), i++;
    while (i < 20) sha1(g(b, c, d), 0x5a827999u, (x[i] = rotl(x[i - 3] ^ x[i - 8] ^ x[i - 14] ^ x[i - 16], 1))), i++;
    while (i < 40) sha1(f(b, c, d), 0x6ed9eba1u, (x[i] = rotl(x[i - 3] ^ x[i - 8] ^ x[i - 14] ^ x[i - 16], 1))), i++;
    while (i < 60) sha1(k(b, c, d), 0x8f1bbcdcu, (x[i] = rotl(x[i - 3] ^ x[i - 8] ^ x[i - 14] ^ x[i - 16], 1))), i++;
    while (i < 80) sha1(f(b, c, d), 0xca62c1d6u, (x[i] = rotl(x[i - 3] ^ x[i - 8] ^ x[i - 14] ^ x[i - 16], 1))), i++;

    r[0] += a, r[1] += b, r[2] += c, r[3] += d, r[4] += e;
}

static void SHA1(const void *data, size_t len, unsigned char *md)
{
    unsigned i, j, x[80], buf[5] = { 0x67452301u, 0xefcdab89u, 0x98badcfeu, 0x10325476u, 0xc3d2e1f0u }; //initialize buf
    
    for (i = 0; i + 64 <= len; i += 64) { // process data in 64 byte blocks
        for (j = 0; j < 16; j++) x[j] = CFSwapInt32HostToBig(((const unsigned *)data)[i/sizeof(unsigned) + j]);
        SHA1Compress(buf, x);
    }
    
    memset(x, 0, sizeof(*x)*16); // clear x
    for (j = 0; j < len - i; j++) x[j/sizeof(*x)] |= ((const char *)data)[j + i] << ((3 - (j & 3))*8); // last block
    x[j/sizeof(*x)] |= 0x80 << ((3 - (j & 3))*8); // append padding
    if (len - i > 55) SHA1Compress(buf, x), memset(x, 0, sizeof(*x)*16); // length goes to next block
    x[15] = len*8; // append length in bits
    SHA1Compress(buf, x); // finalize
    for (i = 0; i < sizeof(buf)/sizeof(*buf); i++) ((unsigned *)md)[i] = CFSwapInt32HostToBig(buf[i]); // write to md
}

// basic ripemd operation
#define rmd(a, b, c, d, e, f, g, h, i, j) ((a) = rotl((f) + (b) + CFSwapInt32LittleToHost(c) + (d), (e)) + (g),\
                                           (f) = (g), (g) = (h), (h) = rotl((i), 10), (i) = (j), (j) = (a))

// ripemd left line
static const unsigned rl1[] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }, // round 1, id
                      rl2[] = { 7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8 }, // round 2, rho
                      rl3[] = { 3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12 }, // round 3, rho^2
                      rl4[] = { 1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2 }, // round 4, rho^3
                      rl5[] = { 4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13 }; // round 5, rho^4

// ripemd right line
static const unsigned rr1[] = { 5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12 }, // round 1, pi
                      rr2[] = { 6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2 }, // round 2, rho pi
                      rr3[] = { 15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13 }, // round 3, rho^2 pi
                      rr4[] = { 8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14 }, // round 4, rho^3 pi
                      rr5[] = { 12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11 }; // round 5, rho^4 pi

// ripemd left line shifts
static const unsigned sl1[] = { 11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8 }, // round 1
                      sl2[] = { 7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12 }, // round 2
                      sl3[] = { 11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5 }, // round 3
                      sl4[] = { 11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12 }, // round 4
                      sl5[] = { 9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6 }; // round 5

// ripemd right line shifts
static const unsigned sr1[] = { 8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6 }, // round 1
                      sr2[] = { 9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11 }, // round 2
                      sr3[] = { 9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5 }, // round 3
                      sr4[] = { 15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8 }, // round 4
                      sr5[] = { 8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11 }; // round 5

static void RMDcompress(unsigned *b, unsigned *x)
{
    unsigned al = b[0], bl = b[1], cl = b[2], dl = b[3], el = b[4], ar = al, br = bl, cr = cl, dr = dl, er = el, i, t;

    // round 1
    for (i = 0; i < 16; i++) rmd(t, f(bl, cl, dl), x[rl1[i]], 0x00000000u, sl1[i], al, el, dl, cl, bl); // left line
    for (i = 0; i < 16; i++) rmd(t, j(br, cr, dr), x[rr1[i]], 0x50a28be6u, sr1[i], ar, er, dr, cr, br); // right line
    
    // round 2
    for (i = 0; i < 16; i++) rmd(t, g(bl, cl, dl), x[rl2[i]], 0x5a827999u, sl2[i], al, el, dl, cl, bl); // left line
    for (i = 0; i < 16; i++) rmd(t, i(br, cr, dr), x[rr2[i]], 0x5c4dd124u, sr2[i], ar, er, dr, cr, br); // right line
    
    // round 3
    for (i = 0; i < 16; i++) rmd(t, h(bl, cl, dl), x[rl3[i]], 0x6ed9eba1u, sl3[i], al, el, dl, cl, bl); // left line
    for (i = 0; i < 16; i++) rmd(t, h(br, cr, dr), x[rr3[i]], 0x6d703ef3u, sr3[i], ar, er, dr, cr, br); // right line
    
    // round 4
    for (i = 0; i < 16; i++) rmd(t, i(bl, cl, dl), x[rl4[i]], 0x8f1bbcdcu, sl4[i], al, el, dl, cl, bl); // left line
    for (i = 0; i < 16; i++) rmd(t, g(br, cr, dr), x[rr4[i]], 0x7a6d76e9u, sr4[i], ar, er, dr, cr, br); // right line
    
    // round 5
    for (i = 0; i < 16; i++) rmd(t, j(bl, cl, dl), x[rl5[i]], 0xa953fd4eu, sl5[i], al, el, dl, cl, bl); // left line
    for (i = 0; i < 16; i++) rmd(t, f(br, cr, dr), x[rr5[i]], 0x00000000u, sr5[i], ar, er, dr, cr, br); // right line
    
    t = b[1] + cl + dr; // final result for b[0]
    b[1] = b[2] + dl + er, b[2] = b[3] + el + ar, b[3] = b[4] + al + br, b[4] = b[0] + bl + cr, b[0] = t; // combine
    memset(x, 0, sizeof(*x)*16); // clear x
}

// ripemd-160 hash function: http://homes.esat.kuleuven.be/~bosselae/ripemd160.html
static void RMD160(const void *data, size_t len, unsigned char *md)
{
    unsigned buf[] = { 0x67452301u, 0xefcdab89u, 0x98badcfeu, 0x10325476u, 0xc3d2e1f0u }, // initial buffer values
             x[] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, i;
    
    for (i = 0; i <= len; i += sizeof(x)) { // process data in 64 byte blocks
        memcpy(x, (const unsigned char *)data + i, (i + sizeof(x) < len) ? sizeof(x) : len - i);
        if (i + sizeof(x) > len) break;
        RMDcompress(buf, x);
    }
    
    ((unsigned char *)x)[len - i] = 0x80; // append padding
    if (len - i > 55) RMDcompress(buf, x); // length goes to next block
    *(unsigned long long *)&x[14] = CFSwapInt64HostToLittle((unsigned long long)len*8); // append length in bits
    RMDcompress(buf, x); // finalize
    for (i = 0; i < sizeof(buf)/sizeof(*buf); i++) ((unsigned *)md)[i] = CFSwapInt32HostToLittle(buf[i]); // write to md
}

@implementation NSData (Bitcoin)

- (UInt128)SHA1
{
    UInt128 sha1;

    SHA1(self.bytes, self.length, (unsigned char *)&sha1);
    return sha1;
}

- (UInt256)SHA256
{
    UInt256 sha256;
    
    CC_SHA256(self.bytes, (CC_LONG)self.length, (unsigned char *)&sha256);
    return sha256;
}

- (UInt256)SHA256_2
{
    UInt256 sha256;
    
    CC_SHA256(self.bytes, (CC_LONG)self.length, (unsigned char *)&sha256);
    CC_SHA256((const void *)&sha256, (CC_LONG)sizeof(sha256), (unsigned char *)&sha256);
    return sha256;
}

- (UInt160)RMD160
{
    UInt160 rmd160;
    
    RMD160(self.bytes, (size_t)self.length, (uint8_t *)&rmd160);
    return rmd160;
}

- (UInt160)hash160
{
    UInt256 sha256;
    UInt160 rmd160;
    
    CC_SHA256(self.bytes, (CC_LONG)self.length, (unsigned char *)&sha256);
    RMD160(&sha256, sizeof(sha256), (uint8_t *)&rmd160);
    return rmd160;
}

- (NSData *)reverse
{
    NSUInteger len = self.length;
    NSMutableData *d = [NSMutableData dataWithLength:len];
    uint8_t *b1 = d.mutableBytes;
    const uint8_t *b2 = self.bytes;
    
    for (NSUInteger i = 0; i < len; i++) {
        b1[i] = b2[len - i - 1];
    }
    
    return d;
}

- (uint8_t)UInt8AtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(uint8_t)) return 0;
    return *((const uint8_t *)self.bytes + offset);
}

- (uint16_t)UInt16AtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(uint16_t)) return 0;
    return CFSwapInt16LittleToHost(*(const uint16_t *)((const uint8_t *)self.bytes + offset));
}

- (uint32_t)UInt32AtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(uint32_t)) return 0;
    return CFSwapInt32LittleToHost(*(const uint32_t *)((const uint8_t *)self.bytes + offset));
}

- (uint64_t)UInt64AtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(uint64_t)) return 0;
    return CFSwapInt64LittleToHost(*(const uint64_t *)((const uint8_t *)self.bytes + offset));
}

- (uint64_t)varIntAtOffset:(NSUInteger)offset length:(NSUInteger *)length
{
    uint8_t h = [self UInt8AtOffset:offset];

    switch (h) {
        case VAR_INT16_HEADER:
            if (length) *length = sizeof(h) + sizeof(uint16_t);
            return [self UInt16AtOffset:offset + 1];
            
        case VAR_INT32_HEADER:
            if (length) *length = sizeof(h) + sizeof(uint32_t);
            return [self UInt32AtOffset:offset + 1];
            
        case VAR_INT64_HEADER:
            if (length) *length = sizeof(h) + sizeof(uint64_t);
            return [self UInt64AtOffset:offset + 1];
            
        default:
            if (length) *length = sizeof(h);
            return h;
    }
}

- (UInt256)hashAtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(UInt256)) return UINT256_ZERO;
    return *(const UInt256 *)((const char *)self.bytes + offset);
}

- (NSString *)stringAtOffset:(NSUInteger)offset length:(NSUInteger *)length
{
    NSUInteger ll, l = (NSUInteger)[self varIntAtOffset:offset length:&ll];
    
    if (length) *length = ll + l;
    if (ll == 0 || self.length < offset + ll + l) return nil;
    return [[NSString alloc] initWithBytes:(const char *)self.bytes + offset + ll length:l
            encoding:NSUTF8StringEncoding];
}

- (NSData *)dataAtOffset:(NSUInteger)offset length:(NSUInteger *)length
{
    NSUInteger ll, l = (NSUInteger)[self varIntAtOffset:offset length:&ll];
    
    if (length) *length = ll + l;
    if (ll == 0 || self.length < offset + ll + l) return nil;
    return [self subdataWithRange:NSMakeRange(offset + ll, l)];
}

// an array of NSNumber and NSData objects representing each script element
- (NSArray *)scriptElements
{
    NSMutableArray *a = [NSMutableArray array];
    const uint8_t *b = (const uint8_t *)self.bytes;
    NSUInteger l, length = self.length;
    
    for (NSUInteger i = 0; i < length; i += l) {
        if (b[i] > OP_PUSHDATA4) {
            l = 1;
            [a addObject:@(b[i])];
            continue;
        }
        
        switch (b[i]) {
            case 0:
                l = 1;
                [a addObject:@(0)];
                continue;

            case OP_PUSHDATA1:
                i++;
                if (i + sizeof(uint8_t) > length) return a;
                l = b[i];
                i += sizeof(uint8_t);
                break;

            case OP_PUSHDATA2:
                i++;
                if (i + sizeof(uint16_t) > length) return a;
                l = CFSwapInt16LittleToHost(*(uint16_t *)&b[i]);
                i += sizeof(uint16_t);
                break;

            case OP_PUSHDATA4:
                i++;
                if (i + sizeof(uint32_t) > length) return a;
                l = CFSwapInt32LittleToHost(*(uint32_t *)&b[i]);
                i += sizeof(uint32_t);
                break;

            default:
                l = b[i];
                i++;
                break;
        }
        
        if (i + l > length) return a;
        [a addObject:[NSData dataWithBytes:&b[i] length:l]];
    }
    
    return a;
}

// returns the opcode used to store the receiver in a script (i.e. OP_PUSHDATA1)
- (int)intValue
{
    if (self.length < OP_PUSHDATA1) return (int)self.length;
    else if (self.length <= UINT8_MAX) return OP_PUSHDATA1;
    else if (self.length <= UINT16_MAX) return OP_PUSHDATA2;
    else return OP_PUSHDATA4;
}

@end
