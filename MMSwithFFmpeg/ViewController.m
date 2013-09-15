//
//  ViewController.m
//  MMSwithFFmpeg
//
//  Created by shouian on 13/8/17.
//  Copyright (c) 2013年 shouian. All rights reserved.
//

#import "ViewController.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#import "Audio/AudioPacketQueue.h"
#import "Audio/AudioPlayer.h"
#import "Audio/AudioUtilities.h"

NSString *const kAudioTestPath = @"mms://bcr.media.hinet.net/RA000009";

typedef enum {
    kTCP = 0,
    kUDP
}kNetworkWay;

@interface ViewController ()
{
    AVFormatContext *pFormatCtx;
    AVCodecContext *pAudioCodeCtx;
    
    int    audioStream;
    
    AudioPlayer *aPlayer;
    BOOL  isStop;
    BOOL  isLocalFile;
    
}

- (void)playAudio:(id)sender;
- (void)stopPlayAudio;
- (BOOL)initFFmpegAudioStream:(NSString *)filePath withTransferWay:(kNetworkWay)network;
- (void)readFFmpegAudioFrameAndDecode;
- (void)stopFFmpegAudioStream;
- (void)destroyFFmpegAudioStream;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    UIButton *playingButton = [[UIButton alloc] initWithFrame:CGRectMake(50, 50, 150, 40)];
    [playingButton setBackgroundColor:[UIColor blackColor]];
    [playingButton setTitle:@"Play" forState:UIControlStateNormal];
    [playingButton addTarget:self action:@selector(playAudio:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:playingButton];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - AudioPlayer Action
- (void)playAudio:(id)sender
{
    UIButton *btn = (UIButton *)sender;
    
    if ([btn.currentTitle isEqualToString:@"Stop"]) {
        [btn setTitle:@"Play" forState:UIControlStateNormal];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self stopPlayAudio];
        });
    } else {
        // Succeed to play audio
        /// TODO: determine if this streaming support ffmpeg
        [btn setTitle:@"Stop" forState:UIControlStateNormal];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            if ([self initFFmpegAudioStream:kAudioTestPath withTransferWay:kTCP] == NO) {
                NSLog(@"Init ffmpeg failed");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [btn setTitle:@"Play" forState:UIControlStateNormal];
                });
                return;
            }
            
            aPlayer = [[AudioPlayer alloc] initAuido:nil withCodecCtx:(AVCodecContext *)pAudioCodeCtx];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                sleep(5);
                if ([aPlayer getStatus] != eAudioRunning) {
                    [aPlayer play];
                }
            });
            
            // Read Packet in another thread
            [self readFFmpegAudioFrameAndDecode];
            
        });
        // Read ffmpeg audio packet in another thread
        
    }
}
- (void)stopPlayAudio
{
    [self stopFFmpegAudioStream];
    [aPlayer stop:YES];
    [self destroyFFmpegAudioStream];
}
#pragma mark - FFmpeg processing
- (BOOL)initFFmpegAudioStream:(NSString *)filePath withTransferWay:(kNetworkWay)network
{
    NSString *pAudioInPath;
    AVCodec  *pAudioCodec;
    
    // Parse header 
    uint8_t pInput[] = {0x0ff,0x0f9,0x058,0x80,0,0x1f,0xfc};
    tAACADTSHeaderInfo vxADTSHeader={0};
    [AudioUtilities parseAACADTSHeader:pInput toHeader:(tAACADTSHeaderInfo *) &vxADTSHeader];
    
    // Compare the file path
    if (strncmp([filePath UTF8String], "rtsp", 4) == 0) {
        pAudioInPath = filePath;
        isLocalFile = NO;
    } else if (strncmp([filePath UTF8String], "mms:", 4) == 0) {
        pAudioInPath = filePath;
        pAudioInPath = [pAudioInPath stringByReplacingOccurrencesOfString:@"mms:" withString:@"mmsh:"];
        NSLog(@"Audio path %@", pAudioInPath);
        isLocalFile = NO;
    } else if (strncmp([filePath UTF8String], "mmsh:", 4) == 0) {
        pAudioInPath = filePath;
        isLocalFile = NO;
    } else {
        pAudioInPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:filePath];
        isLocalFile = YES;
    }
    
    // Register FFmpeg
    avcodec_register_all();
    av_register_all();
    if (isLocalFile == NO) {
        avformat_network_init();
    }
    
    @synchronized(self) {
        pFormatCtx = avformat_alloc_context();
    }
    
    // Set network path 
    switch (network) {
        case kTCP:
        {
            AVDictionary *option = 0;
            av_dict_set(&option, "rtsp_transport", "tcp", 0);
            // Open video file
            if (avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, &option) != 0) {
                NSLog(@"Could not open connection");
                return NO;
            }
            av_dict_free(&option);
        }
            break;
        case kUDP:
        {
            if (avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0) {
                NSLog(@"Could not open connection");
                return NO;
            }
        }
            break;
    }
    
    pAudioInPath = nil;
    
    // Retrieve stream information
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
        NSLog(@"Could not find streaming information");
        return NO;
    }
    
    // Dump Streaming information
    av_dump_format(pFormatCtx, 0, [pAudioInPath UTF8String], 0);
    
    // Find the first audio stream
    if ((audioStream = av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &pAudioCodec, 0)) < 0) {
        NSLog(@"Could not find a audio streaming information");
        return NO;
    } else {
        // Succeed to get streaming information
        NSLog(@"== Audio pCodec Information");
        NSLog(@"name = %s",pAudioCodec->name);
        NSLog(@"sample_fmts = %d",*(pAudioCodec->sample_fmts));
        
        if (pAudioCodec->profiles) {
            NSLog(@"Profile names = %@", pAudioCodec->profiles);
        } else {
            NSLog(@"Profile is Null");
        }
        
        // Get a pointer to the codec context for the video stream
        pAudioCodeCtx = pFormatCtx->streams[audioStream]->codec;
        
        // Find out the decoder
        pAudioCodec = avcodec_find_decoder(pAudioCodeCtx->codec_id);
        
        // Open codec
        if (avcodec_open2(pAudioCodeCtx, pAudioCodec, NULL) < 0) {
            return NO;
        }
    }
    
    isStop = NO;
    
    return YES;
}

- (void)readFFmpegAudioFrameAndDecode
{
    int error;
    AVPacket aPacket;
    av_init_packet(&aPacket);
    
    if (isLocalFile) {
        // Local File playing
        while (isStop == NO) {
            // Read frame
            error = av_read_frame(pFormatCtx, &aPacket);
            if (error == AVERROR_EOF) {
                // End of playing music
                isStop = YES;
            } else if (error == 0) {
                // During playing..
                if (aPacket.stream_index == audioStream) {
                    if ([aPlayer putAVPacket:&aPacket] <=0 ) {
                        NSLog(@"Put Audio packet error");
                    }
                    // For local file, packet should delay
                    usleep(1000 * 25);
                } else {
                    av_free_packet(&aPacket);
                }
            } else {
                // Error occurs
                NSLog(@"av_read_frame error :%s", av_err2str(error));
                isStop = YES;
            }
        }
    } else {
        
        // Remote File playing
        while (isStop == NO) {
            // Read frame
            error = av_read_frame(pFormatCtx, &aPacket);
            if (error == AVERROR_EOF) {
                // End of playing music
                isStop = YES;
            } else if (error == 0) {
                // During playing..
                if (aPacket.stream_index == audioStream) {
                     if ([aPlayer putAVPacket:&aPacket] <=0 ) {
                         NSLog(@"Put Audio packet error");
                    }
                } else {
                    av_free_packet(&aPacket);
                }
            } else {
                // Error occurs
                NSLog(@"av_read_frame error :%s", av_err2str(error));
                isStop = YES;
            }
        }
    }
    
    NSLog(@"End of playing ffmpeg");
    
}

- (void)stopFFmpegAudioStream
{
    isStop = YES;
}
- (void)destroyFFmpegAudioStream
{
    avformat_network_deinit();
}
@end
