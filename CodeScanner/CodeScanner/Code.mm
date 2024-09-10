//
//  KikCodes.m
//  CodeScanner
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#import "Code.h"
#import "kikcodes.h"
#import "kikcode_scan.h"

#define TOTAL_BYTE_COUNT    39
#define MAIN_BYTE_COUNT     35
#define DATA_BYTE_COUNT     22
#define PAYLOAD_BYTE_COUNT  20
#define ECC_BYTE_COUNT      13

#define ZERO_BYTES { 0 }

@implementation KikCodes

+ (nonnull NSData *)encode:(nonnull NSData *)data {
    unsigned char outData[MAIN_BYTE_COUNT] = ZERO_BYTES;
    
    uint8_t bytes[PAYLOAD_BYTE_COUNT] = ZERO_BYTES;
    memcpy(bytes, data.bytes, data.length);
    
    kikCodeEncodeRemote(outData, (unsigned char *)bytes, 0);
//    kikCodeEncodeGroup(outData, (unsigned char *)data.bytes, 0);
    
    return [[NSData alloc] initWithBytes:outData length:MAIN_BYTE_COUNT];
}

+ (nonnull NSData *)decode:(nonnull NSData *)data {
    KikCodePayload payload;
    unsigned int type;
    unsigned int color;
    kikCodeDecode((unsigned char *)data.bytes, &type, &payload, &color);
    
    // Trim any tail zero bytes at the tail
    
    uint8_t *bytes = payload.group.invite_code;
    int length = sizeof(payload.group.invite_code);
    while (length > 0 && bytes[length - 1] == 0x0) {
        length--;
    }
    
    return [[NSData alloc] initWithBytes:bytes length:length];
}

+ (nullable NSData *)scan:(nonnull NSData *)data width:(NSInteger)width height:(NSInteger)height {
    [self scan:data width:width height:height quality:KikCodesScanQualityHigh];
}

+ (nullable NSData *)scan:(nonnull NSData *)data width:(NSInteger)width height:(NSInteger)height quality:(KikCodesScanQuality)quality {
    uint8_t outData[MAIN_BYTE_COUNT] = ZERO_BYTES;
    
    unsigned int qualityValue = [self deviceQualityForScanQuality:quality];
    
    int result = kikCodeScan((unsigned char *)data.bytes, (unsigned int)width, (unsigned int)height, qualityValue, outData, nil, nil, nil, nil);
    if (result == 0) {
        return [[NSData alloc] initWithBytes:outData length:MAIN_BYTE_COUNT];
    }
    return nil;
}

+ (int)deviceQualityForScanQuality:(KikCodesScanQuality)quality {
    switch (quality) {
        case KikCodesScanQualityLow:
            return 0;
        case KikCodesScanQualityMedium:
            return 3;
        case KikCodesScanQualityHigh:
            return 8;
        case KikCodesScanQualityBest:
            return 10;
        default:
            return 8;
    }
}

@end
