//
//  AudioPlayer.h
//  MMSwithFFmpeg
//
//  Created by shouian on 13/8/19.
//  Copyright (c) 2013年 shouian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioPacketQueue.h"
#include "libavformat/avformat.h"
#include "libavutil/opt.h"
#include "libswresample/swresample.h"

typedef enum {
    eAudioRunning   = 1,
    eAudioStop      = 2
}eAudioType;

@interface AudioPlayer : NSObject

@property BOOL bIsADTSAAS;

- (id)initAuido:(AudioPacketQueue *)audioQueue withCodecCtx:(AVCodecContext *)aCodecCtx;
- (void)play;
- (void)stop:(BOOL)bStopImmediatelly;
- (void)decodeAudioFile:(NSString *)filePathIn
              toPCMFile:(NSString *)filePathOut
             withCodecCtx:(AVCodecContext *)pAudioCodecCtx
             withFormat:(AVFormatContext *)pFormatCtx
          withStreamIdx:(int)audioStream;
- (int)getStatus;
- (int)putAVPacket:(AVPacket *)pkt;
- (int)getAVPacket:(AVPacket *)pkt;
- (void)freeAVPacket:(AVPacket *)pkt;

@end
