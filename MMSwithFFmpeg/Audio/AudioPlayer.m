//
//  AudioPlayer.m
//  MMSwithFFmpeg
//
//  Created by shouian on 13/8/19.
//  Copyright (c) 2013年 shouian. All rights reserved.
//

#import "AudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "AudioUtilities.h"

// According to Apple guide, the number of audio queue buffers is recommended to 3
#define NUM_BUFFER                      3
#define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000
#define AUDIO_BUFFER_SECONDS            1
#define AUDIO_BUFFER_QUANTITY           3
#define DECODE_AUDIO_BY_FFMPEG          1

@interface AudioPlayer ()
{
    // ==  This is just refereneced from Apple Queue Service Programming Guide
    // =============================================================
    AudioStreamBasicDescription mDataFormat;                // Represent the audio format 
    AudioQueueRef               mQueue;                     // The playback audio queue created by this app
    AudioQueueBufferRef         mBuffers[NUM_BUFFER];       // An array holding pointers to the audio queue buffer 
    AudioFileID                 mAudioFile;                 // Audio file representing the audio file you want to play
    UInt32                      bufferByteSize;             // size in bytes for each audio queue, use DervieBufferSize to get
    SInt64                      mCurrentPacket;             // The packet index for the next packet to play in your audiio
    UInt32                      mNumPacketsToRead;          // Number of packets to read on each audio queue's callback
    AudioStreamPacketDescription *mPacketDescs;             // For VBR audio data, the array of packet descriptions for the file being played. For CBR data, the value of this field is NULL.
    bool                        mIsRunning;                 // A boolean value indicates the audio queue is running or not
    // =============================================================
    
    bool isFormatVBR;
    AVCodecContext              *aCodecCtx;
    AudioPacketQueue            *audioPacketQueue;
    AVFrame                     *pAudioFrame;
    SwrContext                  *pSwrCtx;
    
    long lastStartTime;
    
}
- (UInt32)putAVPacketsIntoAudioQueue:(AudioQueueBufferRef)audioQueueBuffer;
- (int)DeriveBufferSize:(AudioStreamBasicDescription)ASBdescription withPakcetSize:(UInt32)maxPacketSize andSeconds:(Float64)seconds;
@end

@implementation AudioPlayer

// Reference to Apple "Audio Queue Service Programming Guide" as HandleOutputBuffer Function
void HandleOutputBuffer(void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    // inAQ owns the audio queue's callback
    // inBuffer is an audio queue buffer that the callback is to fill with data by reading from an audio file
    AudioPlayer *player = (AudioPlayer *)aqData;
    [player putAVPacketsIntoAudioQueue:inBuffer];
}

- (id)initAuido:(AudioPacketQueue *)audioQueue withCodecCtx:(AVCodecContext *)pAudioCodecCtx
{
    int i = 0;
    int audio_index = 1;
    int vBufferSize = 0;
    int err;
    
    // Support audio play when screen is locked
    NSError *setCategoryError = nil;
    NSError *activationError = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&setCategoryError];
    [[AVAudioSession sharedInstance] setActive:YES error:&activationError];
    
    if (audioQueue) {
        audioPacketQueue = audioQueue;
    } else {
        audioPacketQueue = [[AudioPacketQueue alloc] initQueue];
    }
    
    aCodecCtx = pAudioCodecCtx;
    pAudioFrame = avcodec_alloc_frame();
    
    if (audio_index >= 0) {
        
        AudioStreamBasicDescription audioFormat = {0};
        audioFormat.mFormatID = -1;
        audioFormat.mSampleRate = pAudioCodecCtx->sample_rate;
        audioFormat.mFormatFlags = 0;
        
        switch (pAudioCodecCtx->codec_id) {
            case AV_CODEC_ID_WMAV1:
            case AV_CODEC_ID_WMAV2:
                audioFormat.mFormatID = kAudioFormatLinearPCM;
                break;
            case AV_CODEC_ID_MP3:
                audioFormat.mFormatID = kAudioFormatMPEGLayer3;
                break;
            case AV_CODEC_ID_AAC:
                audioFormat.mFormatID = kAudioFormatMPEG4AAC;
                audioFormat.mFormatFlags = kMPEG4Object_AAC_Main;
                break;
            case AV_CODEC_ID_PCM_ALAW:
                audioFormat.mFormatID = kAudioFormatALaw;
                break;
            case AV_CODEC_ID_PCM_MULAW:
                audioFormat.mFormatID = kAudioFormatULaw;
                break;
            case AV_CODEC_ID_PCM_U8:
                audioFormat.mFormatID = kAudioFormatLinearPCM;
                break;
            default:
                NSLog(@"Error: audio format '%s' (%d) is not supported", pAudioCodecCtx->codec_name, pAudioCodecCtx->codec_id);
                audioFormat.mFormatID = kAudioFormatAC3;
                break;
        }
        
        
        if (audioFormat.mFormatID != -1) {

            audioFormat.mFormatID = kAudioFormatLinearPCM;
            audioFormat.mFormatFlags = kAudioFormatFlagsCanonical;
            audioFormat.mSampleRate = pAudioCodecCtx->sample_rate;
            audioFormat.mBitsPerChannel = 8 * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            audioFormat.mChannelsPerFrame = pAudioCodecCtx->channels;
            audioFormat.mBytesPerFrame  = pAudioCodecCtx->channels * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            audioFormat.mBytesPerPacket = pAudioCodecCtx->channels * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            audioFormat.mFramesPerPacket = 1;
            audioFormat.mReserved = 0;
            
            // The default data defined by Apple is 16 bits
            // If we got 32 or 8 bits, then convert it into 16 bits
            if (pAudioCodecCtx->sample_fmt == AV_SAMPLE_FMT_FLTP) {
                if (pAudioCodecCtx->channel_layout != 0) {
                    pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                                 pAudioCodecCtx->channel_layout,
                                                 AV_SAMPLE_FMT_S16,
                                                 pAudioCodecCtx->sample_rate,
                                                 pAudioCodecCtx->channel_layout,
                                                 AV_SAMPLE_FMT_FLTP,
                                                 pAudioCodecCtx->sample_rate,
                                                 0,
                                                 0);
                } else {
                    pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                                 pAudioCodecCtx->channels + 1,
                                                 AV_SAMPLE_FMT_S16,
                                                 pAudioCodecCtx->sample_rate,
                                                 pAudioCodecCtx->channels+1,
                                                 AV_SAMPLE_FMT_FLTP,
                                                 pAudioCodecCtx->sample_rate,
                                                 0,
                                                 0);
                }
                NSLog(@"sample_rate=%d, channels=%d, channel_layout=%lld",pAudioCodecCtx->sample_rate, pAudioCodecCtx->channels, pAudioCodecCtx->channel_layout);
                if (swr_init(pSwrCtx)<0) {
                    NSLog(@"swr_init() for AV_SAMPLE_FMT_FLTP fail");
                    return nil;
                }
            } else if(pAudioCodecCtx->sample_fmt == AV_SAMPLE_FMT_S16P) {
                pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                             pAudioCodecCtx->channel_layout,
                                             AV_SAMPLE_FMT_S16,
                                             pAudioCodecCtx->sample_rate,
                                             pAudioCodecCtx->channel_layout,
                                             AV_SAMPLE_FMT_S16P,
                                             pAudioCodecCtx->sample_rate,
                                             0,
                                             0);
                if(swr_init(pSwrCtx)<0)
                {
                    NSLog(@"swr_init() for AV_SAMPLE_FMT_S16P fail");
                    return nil;
                }
            } else if (pAudioCodecCtx->sample_fmt == AV_SAMPLE_FMT_U8)
            {
                pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                             1,
                                             AV_SAMPLE_FMT_S16,
                                             pAudioCodecCtx->sample_rate, 1,
                                             AV_SAMPLE_FMT_U8,
                                             pAudioCodecCtx->sample_rate,
                                             0,
                                             0);
                if(swr_init(pSwrCtx)<0)
                {
                    NSLog(@"swr_init()  fail");
                    return nil;
                }
            }
            
            if ((err = AudioQueueNewOutput(&audioFormat, HandleOutputBuffer, (void *)(self), NULL, NULL, 0, &mQueue)) != noErr) {
                NSLog(@"Error creating audio output queue");
            } else {
                // Succeed to create a new queue to handle output buffer
                if (pAudioCodecCtx->bit_rate == 0) {
                    pAudioCodecCtx->bit_rate = 0x100000; // 1048576 bits
                }
                
                if (pAudioCodecCtx->frame_size == 0) {
                    pAudioCodecCtx->frame_size = 1024;
                }
                
                vBufferSize = [self DeriveBufferSize:audioFormat withPakcetSize:pAudioCodecCtx->bit_rate/8 andSeconds:AUDIO_BUFFER_SECONDS];
                for (i = 0; i < AUDIO_BUFFER_QUANTITY; i++) {
                    if ((err = AudioQueueAllocateBufferWithPacketDescriptions(mQueue, vBufferSize, 1, &mBuffers[i])) != noErr) {
                        NSLog(@"Error when allocating audio buffer");
                        AudioQueueDispose(mQueue, YES);
                        break;
                    }
                }
                
            }
        } /* End of if */
    }
    Float32 gain = 1.0;
    AudioQueueSetParameter(mQueue, kAudioQueueParam_Volume, gain);
    return self;
}

#pragma mark - Public Method
- (int)putAVPacket:(AVPacket *)pkt
{
    return [audioPacketQueue putAVPacket:pkt];
}

- (int)getAVPacket:(AVPacket *)pkt
{
    return [audioPacketQueue getAVPacket:pkt];
}

- (void)freeAVPacket:(AVPacket *)pkt
{
    [audioPacketQueue freeAVPacket:pkt];
}

- (int)getStatus
{
    if (mIsRunning == true) {
        return eAudioRunning;
    } else {
        return eAudioStop;
    }
}

- (void)play
{
    OSStatus err = noErr;
    
    mIsRunning = true;
    lastStartTime = 0;
    
    for (int i = 0; i < AUDIO_BUFFER_QUANTITY; i++) {
        [self putAVPacketsIntoAudioQueue:mBuffers[i]];
    }
    
    err = AudioQueueStart(mQueue, nil); // Start to play audio
    
    if (err != noErr) {
        NSLog(@"AudioQueue Start error %ld", err);
    }

}

- (void)stop:(BOOL)bStopImmediatelly
{
    mIsRunning = false;
    AudioQueueStop(mQueue, bStopImmediatelly); // Stop playing audio
    
    // Disposing of the audio queue also disposes of all its resources, including its buffers.
    AudioQueueDispose(mQueue, bStopImmediatelly);
    
    if (pSwrCtx) {
        swr_free(&pSwrCtx);
    }
    
    if (pAudioFrame) {
        avcodec_free_frame(&pAudioFrame);
    }
    
    NSLog(@"Dispose apple audio queue");
    
}

// Reference to Apple "Audio Queue Service Programming Guide" in page 48. (2010)
- (int)DeriveBufferSize:(AudioStreamBasicDescription)ASBdescription withPakcetSize:(UInt32)maxPacketSize andSeconds:(Float64)seconds
{
    // An upper bound for the audio queue buffer size, in bytes. In this example, the upper bound is set to 320
    // KB. This corresponds to approximately five seconds of stereo, 24 bit audio at a sample rate of 96 kHz
    static const int maxBufferSize = 0x50000;   // 327680 bytes
    // A lower bound for the audio queue buffer size, in bytes. In this example, the lower bound is set to 16 KB.
    static const int minBufferSize = 0x4000;    // 16384 bytes
    int outBufferSize = 0;
    
    if (ASBdescription.mFramesPerPacket != 0) {
        Float64 numPacketForTime = ASBdescription.mSampleRate / ASBdescription.mFramesPerPacket;
        outBufferSize = numPacketForTime * maxPacketSize;
    } else {
        outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize : maxPacketSize;
    }
    
    if (outBufferSize > maxBufferSize && outBufferSize > maxPacketSize) {
        outBufferSize = maxBufferSize;
    } else if (outBufferSize < minBufferSize) {
        outBufferSize = minBufferSize;
    }
    
    return outBufferSize;
}

#pragma mark - Private Method
- (UInt32)putAVPacketsIntoAudioQueue:(AudioQueueBufferRef)audioQueueBuffer
{
    AudioTimeStamp bufferStartTime = {0};
    AVPacket aAudioPacket = {0};
    static int vSlienceCount = 0;
    
    AudioQueueBufferRef bufferRef = audioQueueBuffer;
    
    av_init_packet(&aAudioPacket);
    bufferRef->mAudioDataByteSize = 0;
    bufferRef->mPacketDescriptionCount = 0;
    
    if (mIsRunning == false) {
        return 0;
    }
    
    /// TODO: remove debug log
    NSLog(@"Get 1 from audioPacketQueue: %d", [audioPacketQueue count]);
    // If no data, we put silence audio (PCM format only)
    // If AudioQueue buffer is empty, AudioQueue will stop
    if ([audioPacketQueue count]==0) {
        
        int err, vSlienceDataSize = 1024 * 24;
        
        vSlienceCount++;
        
        NSLog(@"Put Silence -- Need adjust circular buffer");
        
        @synchronized(self) {
            memset(bufferRef->mAudioData, 0, vSlienceDataSize);
            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mStartOffset = bufferRef->mAudioDataByteSize;
            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mDataByteSize = vSlienceDataSize;
            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mVariableFramesInPacket = 1;
            bufferRef->mAudioDataByteSize += vSlienceDataSize;
            bufferRef->mPacketDescriptionCount++;
        }
        
        if ((err = AudioQueueEnqueueBuffer(mQueue, bufferRef, 0, NULL))) {
            NSLog(@"Error when enqueuing audio buffer");
        }
        
        return 1;
    }
    vSlienceCount = 0;
    
    if (bufferRef->mPacketDescriptionCount < bufferRef->mPacketDescriptionCapacity) {
        
        [audioPacketQueue getAVPacket:&aAudioPacket];
        
#if DECODE_AUDIO_BY_FFMPEG == 1 // Decode by FFmpeg
        if (bufferRef->mAudioDataBytesCapacity - bufferRef->mAudioDataByteSize >= aAudioPacket.size) {
            
            uint8_t *pktData = NULL;
            int gotFrame     = 0;
            int pktSize;
            int len = 0;
            AVCodecContext *pAudioCodecCtx = aCodecCtx;
            AVFrame *pAVFrame1 = pAudioFrame;
            pktData = aAudioPacket.data;
            pktSize = aAudioPacket.size;
            
            while (pktSize > 0) {
                
                avcodec_get_frame_defaults(pAVFrame1);
                
                @synchronized(self) {
                    len = avcodec_decode_audio4(pAudioCodecCtx, pAVFrame1, &gotFrame, &aAudioPacket);
                }
                
                if (len < 0) {
                    gotFrame = 0;
                    printf("Error when decoding");
                    break;
                }
                
                if (gotFrame > 0) {
                    int outCount = 0;
                    
                    // For broadcast, av_samples_get_buffer_size() may get incorrect size
                    // pAVFrame1->nb_samples may incorrect, too large
                    int data_size = av_samples_get_buffer_size(pAVFrame1->linesize,
                                                               pAudioCodecCtx->channels,
                                                               pAVFrame1->nb_samples,
                                                               AV_SAMPLE_FMT_S16,
                                                               0);
                    
                    if (bufferRef->mAudioDataBytesCapacity - bufferRef->mAudioDataByteSize >= data_size) {
                        
                        @synchronized(self){
                            uint8_t pTemp[data_size];
                            uint8_t *pOut = (uint8_t *)&pTemp;
                            int in_samples = pAVFrame1->nb_samples;
                            
                            bufferStartTime.mSampleTime = lastStartTime + in_samples;
                            bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
                            lastStartTime = bufferStartTime.mSampleTime;
                            
                            // Convert audio.
                            outCount = swr_convert(pSwrCtx,
                                                   (uint8_t **)(&pOut),
                                                   in_samples,
                                                   (const uint8_t **)pAVFrame1->extended_data,
                                                   in_samples);
                            
                            if (outCount < 0) {
                                NSLog(@"swr_convert failed");
                            }
                            
                            memcpy((uint8_t *)bufferRef->mAudioData + bufferRef->mAudioDataByteSize, pOut, data_size);
                            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mStartOffset = bufferRef->mAudioDataByteSize;
                            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mDataByteSize = data_size;
                            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mVariableFramesInPacket=1;
                            
                            bufferRef->mAudioDataByteSize += data_size;
                        }
                        bufferRef->mPacketDescriptionCount++;
                    }
                    gotFrame = 0;
                }
                pktSize -= len;
                pktData += len;
            }
        }
#else
        if (bufferRef->mAudioDataBytesCapacity-bufferRef->mAudioDataByteSize >= aAudioPacket.size) {
            int vOffsetOfADTS=0;
            uint8_t *pHeader = &(aAudioPacket.data[0]);
            
            // 20130603
            // Parse audio data to see if there is ADTS header
            tAACADTSHeaderInfo vxADTSHeader={0};
            _bIsADTSAAS = [AudioUtilities parseAACADTSHeader:pHeader toHeader:(tAACADTSHeaderInfo *) &vxADTSHeader];
            
            if(_bIsADTSAAS)
            {
                // Remove ADTS Header
                vOffsetOfADTS = 7;
            }
            else
            {
                ; // do nothing
            }
            
            memcpy((uint8_t *)bufferRef->mAudioData + bufferRef->mAudioDataByteSize, aAudioPacket.data + vOffsetOfADTS, aAudioPacket.size - vOffsetOfADTS);
            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mStartOffset = bufferRef->mAudioDataByteSize;
            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mDataByteSize = aAudioPacket.size - vOffsetOfADTS;
            bufferRef->mPacketDescriptions[bufferRef->mPacketDescriptionCount].mVariableFramesInPacket = aCodecCtx->frame_size;
            bufferRef->mAudioDataByteSize += (aAudioPacket.size-vOffsetOfADTS);
            bufferRef->mPacketDescriptionCount++;
        }
#endif
        [audioPacketQueue freeAVPacket:&aAudioPacket];
    }
    
    if (bufferRef->mPacketDescriptionCount > 0) {
        int err;
#if 1  // CBR
        if ((err = AudioQueueEnqueueBuffer(mQueue,
                                           bufferRef,
                                           0,
                                           NULL)))
#else  // VBR
            if ((err = AudioQueueEnqueueBufferWithParameters(mQueue,
                                                             bufferRef,
                                                             0,
                                                             NULL,
                                                             0,
                                                             0,
                                                             0,
                                                             NULL,
                                                             &bufferStartTime,
                                                             NULL)))
#endif
            {
                NSLog(@"Error enqueuing audio buffer: %d", err);
            }
    }
    return 0;
}

#pragma mark - test method
- (void)decodeAudioFile:(NSString *)filePathIn toPCMFile:(NSString *)filePathOut withCodecCtx:(AVCodecContext *)pAudioCodecCtx withFormat:(AVFormatContext *)pFormatCtx withStreamIdx:(int)audioStream
{
    // Test to write a audio file into PCM format file
    FILE *wavFile = NULL;
    AVPacket AudioPacket = {0};
    AVFrame *pAVFrame1;
    int iFrame = 1;
    uint8_t *pktData = NULL;
    int pktSize, audioFileSize = 0;
    int gotFrame = 0;
    
    // Initialize
    pAVFrame1 = av_frame_alloc();
    av_init_packet(&AudioPacket);
    
    // Path
    NSString *absPath = @"/Users/shouian/";
    absPath = [absPath stringByAppendingString:filePathIn];
    // Open file
    wavFile = fopen([absPath UTF8String], "wb");
    if (wavFile == NULL) {
        printf("open file for writing error");
        return;
    }
    
    [AudioUtilities writeWAVHeaderWithCodecCtx:pAudioCodecCtx withFormatCtx:pFormatCtx toFile:wavFile];
    while (av_read_frame(pFormatCtx, &AudioPacket) > 0) {
        if (AudioPacket.stream_index == audioStream) {
            
            int len = 0;
            
            if (iFrame++ >= 4000) {
                break;
            }
            
            pktData = AudioPacket.data;
            pktSize = AudioPacket.size;
            
            while (pktSize > 0) {
                len = avcodec_decode_audio4(pAudioCodecCtx, pAVFrame1, &gotFrame, &AudioPacket);
                
                if (len < 0) {
                    printf("Error when decoding");
                    break;
                }
                
                if (gotFrame > 0) {
                    int data_size = av_samples_get_buffer_size(NULL, pAudioCodecCtx->channels, pAVFrame1->nb_samples, pAudioCodecCtx->sample_fmt, 1);
                    
                    fwrite(pAVFrame1->data[0], 1, data_size, wavFile);
                    audioFileSize += data_size;
                    fflush(wavFile);
                    gotFrame = 0;
                }
                pktSize -= len;
                pktData += len;
            }
        }
        [audioPacketQueue freeAVPacket:&AudioPacket];
    }
    fseek(wavFile, 40, SEEK_SET);
    fwrite(&audioFileSize, 1, sizeof(int32_t), wavFile);
    audioFileSize += 36;
    fseek(wavFile, 4, SEEK_SET);
    fwrite(&audioFileSize, 1, sizeof(int32_t), wavFile);
    fclose(wavFile);
}

@end
