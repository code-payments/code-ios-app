//
//  KikCodes.h
//  CodeScanner
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KikCodes : NSObject

+ (NSData *)encode:(NSData *)data;
+ (NSData *)decode:(NSData *)data;

+ (nullable NSData *)scan:(NSData *)data width:(NSInteger)width height:(NSInteger)height;
+ (nullable NSData *)scan:(NSData *)data width:(NSInteger)width height:(NSInteger)height hd:(BOOL)hd;

@end

NS_ASSUME_NONNULL_END
