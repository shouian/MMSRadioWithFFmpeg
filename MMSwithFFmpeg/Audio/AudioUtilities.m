//
//  AudioUtilities.m
//  MMSwithFFmpeg
//
//  Created by shouian on 13/8/18.
//  Copyright (c) 2013年 shouian. All rights reserved.
//

#import "AudioUtilities.h"

@implementation AudioUtilities

#pragma mark - For specific audio header parser
+ (BOOL)parseAACADTSHeader:(uint8_t *)input toHeader:(tAACADTSHeaderInfo *)ADTSHeader
{
    BOOL bHasSyncword = NO;
    
    if (ADTSHeader == nil) {
        return FALSE;
    }
    
    // ADTS Fixed Header
    // syncword; 12 bslbf should be 0x1111 1111 1111
    if (input[0] == 0xFF) {
        if ((input[1] & 0xF0) == 0xF0) {
            bHasSyncword = YES;
        }
    }
    
    if (bHasSyncword == NO) {
        return FALSE;
    }
    
    //== adts_fixed_header ==
    //    uint16_t   syncword;                // 12 bslbf
    //    uint8_t    ID;                       // 1 bslbf
    //    uint8_t    layer;                    // 2 uimsbf
    //    uint8_t    protection_absent;        // 1 bslbf
    //    uint8_t    profile;                  // 2 uimsbf
    //    uint8_t    sampling_frequency_index; // 4 uimsbf
    //    uint8_t    private_bit;              // 1 bslbf
    //    uint8_t    channel_configuration;    // 3 uimsbf
    //    uint8_t    original_copy;            // 1 bslbf
    //    uint8_t    home;                     // 1 bslbf
    
    ADTSHeader->syncword = 0x0fff;
    ADTSHeader->ID = (input[1]&0x08) >> 3;
    ADTSHeader->layer = (input[1]&0x06) >> 2;
    ADTSHeader->protection_absent = input[1]&0x01;
    
    ADTSHeader->profile = (input[2]&0xC0) >> 6;
    ADTSHeader->sampling_frequency_index = (input[2]&0x3C) >> 2;
    ADTSHeader->private_bit = (input[2]&0x02) >> 1;
    
    ADTSHeader->channel_configuration = ((input[2]&0x01)<<2) + ((input[3]&0xC0)>>6);
    ADTSHeader->original_copy = ((input[3]&0x20)>>5);
    ADTSHeader->home = (input[3]&0x10) >> 4;
    
    // == adts_variable_header ==
    //    copyright_identification_bit; 1 bslbf
    //    copyright_identification_start; 1 bslbf
    //    frame_length; 13 bslbf
    //    adts_buffer_fullness; 11 bslbf
    //    number_of_raw_data_blocks_in_frame; 2 uimsfb
    ADTSHeader->copyright_identification_bit = ((input[3]&0x08)>>3);
    ADTSHeader->copyright_identification_start = ((input[3]&0x04)>>2);
    ADTSHeader->frame_length = ((input[3]&0x03)<<11) + ((input[4])<<3) + ((input[5]&0xE0)>>5);
    ADTSHeader->adts_buffer_fullness = ((input[5]&0x1F)<<6) + ((input[6]&0xFC)>>2);
    ADTSHeader->number_of_raw_data_blocks_in_frame = ((input[6]&0x03));
    
    return YES;
}

// TODO in the future for audio recording
- (uint8_t *) generateAACADTSHeader:(uint8_t *) pInOut ToHeader:(tAACADTSHeaderInfo *) pADTSHeader
{
    if(pADTSHeader==nil)
        return NULL;
    
    // adts_fixed_header
    //    syncword; 12 bslbf
    //    ID; 1 bslbf
    //    layer; 2 uimsbf
    //    protection_absent; 1 bslbf
    //    profile; 2 uimsbf
    //    sampling_frequency_index; 4 uimsbf
    //    private_bit; 1 bslbf
    //    channel_configuration; 3 uimsbf
    //    original/copy; 1 bslbf
    //    home; 1 bslbf
    
    // adts_variable_header
    //    copyright_identification_bit; 1 bslbf
    //    copyright_identification_start; 1 bslbf
    //    frame_length; 13 bslbf
    //    adts_buffer_fullness; 11 bslbf
    //    number_of_raw_data_blocks_in_frame; 2 uimsfb
    
    return NULL;
}

+ (int) getMPEG4AudioSampleRates: (uint8_t) vSamplingIndex
{
    int pRates[13] = {
        96000, 88200, 64000, 48000, 44100, 32000,
        24000, 22050, 16000, 12000, 11025, 8000, 7350
    };
    
    if(vSamplingIndex<13)
        return pRates[vSamplingIndex];
    else
        return 0;
}

+ (void)printFileStreamBasicDescription:(AudioStreamBasicDescription *)dataFormat
{
    NSLog(@"mFormatID=%d", (signed int)dataFormat->mFormatID);
    NSLog(@"mFormatFlags=%d", (signed int)dataFormat->mFormatFlags);
    NSLog(@"mSampleRate=%ld", (signed long int)dataFormat->mSampleRate);
    NSLog(@"mBitsPerChannel=%d", (signed int)dataFormat->mBitsPerChannel);
    NSLog(@"mBytesPerFrame=%d", (signed int)dataFormat->mBytesPerFrame);
    NSLog(@"mBytesPerPacket=%d", (signed int)dataFormat->mBytesPerPacket);
    NSLog(@"mChannelsPerFrame=%d", (signed int)dataFormat->mChannelsPerFrame);
    NSLog(@"mFramesPerPacket=%d", (signed int)dataFormat->mFramesPerPacket);
    NSLog(@"mReserved=%d", (signed int)dataFormat->mReserved);
}

+ (void)printFileStreamBasicDescriptionFromFile:(NSString *)filePath
{
    OSStatus status;
    UInt32 size = 0;
    AudioFileID audioFile;
    AudioStreamBasicDescription dataFormat;
    
    // or you can use CFURLCreateFromFileSystemRepresentation to get the url
    CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:filePath];
    
    // Open the audio file to playback
    status = AudioFileOpenURL(url, kAudioFileReadPermission, 0, &audioFile);
    if (size != noErr) {
        NSLog(@"*** Error *** PlayAudio - play:Path: could not open audio file. Path given was: %@", filePath);
        return;
    } else {
        NSLog(@"*** OK *** : %@", filePath);
    }
    
    size = sizeof(dataFormat);
    
    AudioFileGetProperty(audioFile,
                         kAudioFilePropertyDataFormat,
                         &size,
                         &dataFormat);
    
    if (size > 0) {
        [self printFileStreamBasicDescription:&dataFormat];
    }
    
    AudioFileClose(audioFile);
    CFRelease(url);
}

+ (void)writeWAVHeaderWithCodecCtx:(AVCodecContext *)pAudioCodecCtx withFormatCtx:(AVFormatContext *)pFormatCtx toFile:(FILE *)wavFile
{
    char *data;
    int32_t long_temp;
    int16_t short_temp;
    int16_t BlockAlign;
    int32_t fileSize;
    int32_t audioDataSize;
    
    int vBitsPerSample = 0;
    switch (pAudioCodecCtx->sample_rate) {
        case AV_SAMPLE_FMT_S16:
            vBitsPerSample = 16;
            break;
        case AV_SAMPLE_FMT_S32:
            vBitsPerSample = 32;
            return;
        case AV_SAMPLE_FMT_U8:
            vBitsPerSample = 8;
            return;
        default:
            vBitsPerSample = 16;
            break;
    }
    
    audioDataSize = (pFormatCtx->duration) * (vBitsPerSample/8) * pAudioCodecCtx->sample_rate * pAudioCodecCtx->channels;
    
    fileSize = audioDataSize + 36;
    
    // FMT subchunk
    data = "RIFF";                                  // Chunk ID
    fwrite(data, sizeof(char), 4, wavFile);
    fwrite(&fileSize, sizeof(int32_t), 1, wavFile);
    
    // "WAVE"
    data = "WAVE";
    fwrite(data, sizeof(char), 4, wavFile);
    
    // fmt subchunk
    data = "fmt ";
    fwrite(data, sizeof(char), 4, wavFile);
    
    // SubChunkSize (16 for PCM)
    long_temp = 16;
    fwrite(&long_temp, sizeof(int32_t), 1, wavFile);
    
    // AudioFormt, 1=PCM
    short_temp = 0x01;
    fwrite(&short_temp, sizeof(int16_t), 1, wavFile);
    
    // NumChannels (mono=1, stereo=2)
    long_temp =pAudioCodecCtx->channels;
    fwrite(&long_temp, sizeof(int16_t), 1, wavFile);
    
    // Sample Rate (U32)
    long_temp = pAudioCodecCtx->sample_rate;
    fwrite(&long_temp, sizeof(int32_t), 1, wavFile);
    
    // ByteRate (U32)
    long_temp=(vBitsPerSample/8)*(pAudioCodecCtx->channels)*(pAudioCodecCtx->sample_rate);
    fwrite(&long_temp,sizeof(int32_t),1,wavFile);
    
    // BlockAlign (U16)
    BlockAlign=(vBitsPerSample/8)*(pAudioCodecCtx->channels);
    fwrite(&BlockAlign,sizeof(int16_t),1,wavFile);
    
    // BitsPerSample (U16)
    short_temp=(vBitsPerSample);
    fwrite(&short_temp,sizeof(int16_t),1,wavFile);
    
    // =============
    // Data Subchunk
    data="data";                            // Subchunk2ID
    fwrite(data,sizeof(char),4,wavFile);
    
    // SubChunk2Size
    fwrite(&audioDataSize,sizeof(int32_t),1,wavFile);
    
    fseek(wavFile,44,SEEK_SET);
}

// Decode an audio file to PCM file with WAV header
+ (id)initForDecodeAudioFile:(NSString *)filePathIn toPCMFile:(NSString *)filePathOutput
{
    // Test to write a audio file into PCM format file
    FILE *wavFile = NULL;
    AVPacket audioPacket = {0};
    AVFrame *pAVFrame;
    int iFrame = 0;
    uint8_t *pktData = NULL;
    int pktSize, audioFileSize = 0;
    int gotFrame = 0;
    
    AVCodec *pAudioCodec;
    AVCodecContext *pAudioCodeCtx = NULL;
    AVFormatContext *pAudioFormatCtx;
    SwrContext *pSwrCtx = NULL;
    
    int audioStream = -1;
    
    avcodec_register_all(); /*Register all the codecs, parsers and bitstream filters which were enabled at configuration time.*/
    av_register_all(); /* Initialize libavformat and register all the muxers, demuxers and protocols. */
    avformat_network_init(); /*Do global initialization of network components.*/
    
    pAudioFormatCtx = avformat_alloc_context(); /* Allocate an AVFormatContext. */
    
    if (avformat_open_input(&pAudioFormatCtx, [filePathIn cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open file\n");
    }
    
    if (avformat_find_stream_info(pAudioFormatCtx, NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find stream information\n");
    }
    
    av_dump_format(pAudioFormatCtx, 0, [filePathIn UTF8String], 0);
    
    int i;
    for (i = 0; i < pAudioFormatCtx->nb_streams; i++) {
        if (pAudioFormatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO) {
            audioStream = i;
            break;
        }
    }
    
    if (audioStream < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
        return nil;
    }
    
    pAudioCodeCtx = pAudioFormatCtx->streams[audioStream]->codec;
    pAudioCodec = avcodec_find_decoder(pAudioCodeCtx->codec_id);
    if (pAudioCodec == NULL) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
    }
    
    if (pAudioCodeCtx->sample_fmt==AV_SAMPLE_FMT_FLTP) {
        pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                     pAudioCodeCtx->channel_layout,
                                     AV_SAMPLE_FMT_S16,
                                     pAudioCodeCtx->sample_fmt,
                                     pAudioCodeCtx->channel_layout,
                                     AV_SAMPLE_FMT_FLTP,
                                     pAudioCodeCtx->sample_rate,
                                     0,
                                     0);
        if (swr_init(pSwrCtx)<0) {
            return nil;
        }
    } else if (pAudioCodeCtx->bits_per_raw_sample == 8) { // For topview ipcamera pcm_law
        pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                     1,
                                     AV_SAMPLE_FMT_S16,
                                     pAudioCodeCtx->sample_rate,
                                     1,
                                     AV_SAMPLE_FMT_U8,
                                     pAudioCodeCtx->sample_rate,
                                     0,
                                     0);
        if (swr_init(pSwrCtx)<0) {
            return nil;
        }
    }
    
    wavFile = fopen([filePathIn UTF8String], "wb");
    if (wavFile == NULL) {
        printf("open file for writing error");
        return self;
    }
    
    pAVFrame = avcodec_alloc_frame();
    av_init_packet(&audioPacket);
    
    int buffer_size = 19200 + FF_INPUT_BUFFER_PADDING_SIZE;
    uint8_t buffer[buffer_size];
    audioPacket.data = buffer;
    audioPacket.size = buffer_size;
    
    [AudioUtilities writeWAVHeaderWithCodecCtx:pAudioCodeCtx withFormatCtx:pAudioFormatCtx toFile:wavFile];
    
    while (av_read_frame(pAudioFormatCtx, &audioPacket) > 0) {
        
        if (audioPacket.stream_index == audioStream) {
            
            int len = 0;
            
            if (iFrame++ > 4000) {
                break;
            }
            pktData = audioPacket.data;
            pktSize = audioPacket.size;
            
            while (pktSize > 0) {
                len = avcodec_decode_audio4(pAudioCodeCtx, pAVFrame, &gotFrame, &audioPacket);
                if (len < 0) {
                    printf("Error when decoding");
                    break;
                }
                if (gotFrame) {
                    int data_size = av_samples_get_buffer_size(NULL,
                                                               pAudioCodeCtx->channels,
                                                               pAVFrame->nb_samples,
                                                               pAudioCodeCtx->sample_fmt, 1);
                    // Resampling
                    if (pAudioCodeCtx->sample_fmt == AV_SAMPLE_FMT_FLTP) {
                        int in_samples = pAVFrame->nb_samples;
                        int outCount = 0;
                        uint8_t *output = NULL;
                        int out_lineSize;
                        
                        av_samples_alloc(&output,
                                         &out_lineSize,
                                         pAVFrame->channels,
                                         in_samples,
                                         AV_SAMPLE_FMT_S16,
                                         0);
                        outCount = swr_convert(pSwrCtx,
                                               (uint8_t **)&output,
                                               in_samples,
                                               (const uint8_t **)pAVFrame->extended_data,
                                               in_samples);
                        
                        if (outCount < 0) {
                            NSLog(@"swr_convert fail");
                        }
                        
                        fwrite(output, 1, data_size/2, wavFile);
                        audioFileSize += data_size/2;
                        
                    }
                    fflush(wavFile);
                    gotFrame = 0;
                }
                pktSize -= len;
                pktData += len;
            }
        }
        av_free_packet(&audioPacket);
    }
    
    fseek(wavFile, 40, SEEK_SET);
    fwrite(&audioFileSize, 1, sizeof(int32_t), wavFile);
    audioFileSize += 36;
    fseek(wavFile, 4, SEEK_SET);
    fwrite(&audioFileSize, 1, sizeof(int32_t), wavFile);
    fclose(wavFile);
    
    if (pSwrCtx) {
        swr_free(&pSwrCtx);
    }
    
    if (pAVFrame) {
        avcodec_free_frame(&pAVFrame);
    }
    
    if (pAudioCodeCtx) {
        avcodec_close(pAudioCodeCtx);
    }
    if (pAudioFormatCtx) {
        avformat_close_input(&pAudioFormatCtx);
    }
    
    return self;
}

@end
