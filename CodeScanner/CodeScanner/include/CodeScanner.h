//
//  CodeScanner.h
//  CodeScanner
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, KikCodesScanQuality) {
    KikCodesScanQualityLow    NS_SWIFT_NAME(low)    = 0,
    KikCodesScanQualityMedium NS_SWIFT_NAME(medium) = 2,
    KikCodesScanQualityHigh   NS_SWIFT_NAME(high)   = 7,
    KikCodesScanQualityBest   NS_SWIFT_NAME(best)   = 10
} NS_SWIFT_NAME(KikCodesScanQuality);

@interface KikCodes : NSObject

+ (NSData *)encode:(NSData *)data;
+ (NSData *)decode:(NSData *)data;

+ (nullable NSData *)scan:(NSData *)data width:(NSInteger)width height:(NSInteger)height;
+ (nullable NSData *)scan:(NSData *)data width:(NSInteger)width height:(NSInteger)height quality:(KikCodesScanQuality)quality;

@end

NS_ASSUME_NONNULL_END
