//
//  doublesky_rtmp_push.h
//  DoubleSky_Zhang
//
//  Created by zz on 2020/3/26.
//  Copyright © 2020 zz. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface doublesky_rtmp_push : NSObject
- (int)start_rtmp;
- (void)stop_rtmp;

- (void)push_buffer:(char *)buffer size:(int)size is_video:(bool)is_video;
@end

NS_ASSUME_NONNULL_END
