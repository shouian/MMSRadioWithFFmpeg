//
//  AudioPacketQueue.h
//  MMSwithFFmpeg
//
//  Created by shouian on 13/8/17.
//  Copyright (c) 2013年 shouian. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "libavformat/avformat.h"

@interface AudioPacketQueue : NSObject

@property int count;

- (id)initQueue;
- (void)destroyQueue;
- (int)putAVPacket:(AVPacket *)packet;
- (int)getAVPacket:(AVPacket *)packet;
- (void)freeAVPacket:(AVPacket *)packet;

@end
