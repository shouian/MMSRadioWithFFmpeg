//
//  AudioPacketQueue.m
//  MMSwithFFmpeg
//
//  Created by shouian on 13/8/17.
//  Copyright (c) 2013年 shouian. All rights reserved.
//

#import "AudioPacketQueue.h"

@interface AudioPacketQueue()
{
    NSMutableArray *queues;
    NSLock *pLock;
}

@end

@implementation AudioPacketQueue

@synthesize count = _count;

- (id)initQueue
{
    self = [super self];
    if (self) {
        queues = [[NSMutableArray alloc] init];
        pLock = [[NSLock alloc] init];
        _count = 0;
    }
    return self;
}

- (void)dealloc
{
    [self destroyQueue];
    [pLock release];
    [queues release];
    
    [super dealloc];
}

- (void)destroyQueue
{
    AVPacket vxPacket;
    NSMutableData *packetData = nil;
    
    [pLock lock];
    
    // Release all packet in the array
    while ([queues count] > 0) {
        packetData = [queues objectAtIndex:0];
        
        if (packetData != nil) {
            
            [packetData getBytes:&vxPacket length:sizeof(AVPacket)];
            av_free_packet(&vxPacket);
            
            [packetData release];
            packetData = nil;
            
            [queues removeObjectAtIndex:0];
            _count--;
        }
        
    }
    _count = 0;
    [pLock unlock];
    if (queues) {
        queues = nil;
    }
}

// Put packet
- (int)putAVPacket:(AVPacket *)packet
{
    // Protect if memory leakage
    if (av_dup_packet(packet) < 0) {
        NSLog(@"Error occurs when duplicating packet");
    }
    
    [pLock lock];
    
    NSMutableData *tmpData = [[NSMutableData alloc] initWithBytes:packet length:sizeof(*packet)];
    [queues addObject:tmpData];
    
    // Release packet
    [tmpData release];
    tmpData = nil;
    
    _count++;
    [pLock unlock];
    
    return 1;
}

- (int)getAVPacket:(AVPacket *)packet
{
    NSMutableData *packetData = nil;
    
    [pLock lock];
    
    if ([queues count] > 0) {
        packetData = [queues objectAtIndex:0];
        if (packetData != nil) {
            [packetData getBytes:packet];
            
            packetData = nil;
//
            [queues removeObjectAtIndex:0];
            _count--;
        }
        [pLock unlock];
        return 1;
    }
    
    [pLock unlock];
    return 0;
}

- (void)freeAVPacket:(AVPacket *)packet
{
    [pLock lock];
    av_free_packet(packet);
    [pLock unlock];
}

@end
