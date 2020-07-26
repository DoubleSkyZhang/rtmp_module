//
//  doublesky_rtmp_push.m
//  DoubleSky_Zhang
//
//  Created by zz on 2020/3/26.
//  Copyright © 2020 zz. All rights reserved.
//
#include <tuple>
#include <memory>
#include <queue>
#include <thread>

extern "C"
{
    #include <libavformat/avformat.h>
}

#import "doublesky_rtmp_push.h"
class doublesky_ffmpeg_clean
{
public:
    doublesky_ffmpeg_clean() : format_context(NULL), io_context(NULL), video_stream(NULL), audio_stream(NULL)
    {
        av_register_all();
        avformat_network_init();
        av_log_set_level(AV_LOG_DEBUG);
    }
    
    ~doublesky_ffmpeg_clean()
    {
        clean();
    }
    
    void clean()
    {
        if (io_context)
        {
            avio_close(io_context);
            io_context = NULL;
        }
        if (format_context)
        {
            avformat_free_context(format_context);
        }
    }
    
    AVFormatContext *format_context;
    AVIOContext *io_context;
    AVStream *video_stream, *audio_stream;
};
@interface doublesky_rtmp_push()
{
    std::queue<std::tuple<int, std::shared_ptr<char>, bool>> queue;
    std::thread thread;
    std::mutex mutex;
    std::condition_variable cond;
    bool stop, open_success;
    doublesky_ffmpeg_clean ffmpeg_clean;
}
@end
@implementation doublesky_rtmp_push
- (instancetype)init
{
    self = [super init];
    if (!self) return nil;
    thread = std::thread(std::bind([self]
    {
        std::unique_lock<std::mutex> lock(mutex, std::defer_lock);
        while(!stop)
        {
            lock.lock();
            while(queue.empty())
                cond.wait(lock);
            
            // 推流
            [self push_rtmp:std::get<1>(queue.front()).get() size:std::get<0>(queue.front())];
            queue.pop();
            lock.unlock();
        }
    }));
    return self;
}

// ffmpeg -re -i /Users/zz/Downloads/RPReplay_Final1585299840.MP4 -vcodec copy -f flv rtmp://localhost:1935/zbcs/room
- (void)push_buffer:(char *)buffer size:(int)size is_video:(bool)is_video
{
    std::unique_lock<std::mutex> lock(mutex);
    std::shared_ptr<char> ptr(new char[size], std::default_delete<char[]>());
    memcpy(ptr.get(), buffer, size);
    queue.push(std::tuple<int, std::shared_ptr<char>, bool>(size, ptr, is_video));
    lock.unlock();
    cond.notify_one();
}

- (int)start_rtmp
{
    int ret = [self p_start_rtmp];
    if (ret != 0)
        ffmpeg_clean.clean();
    
    return ret;
}

- (void)stop_rtmp
{
    std::unique_lock<std::mutex> lock;
    std::queue<std::tuple<int, std::shared_ptr<char>, bool>> empty;
    std::swap(empty, queue);
    if (open_success)
        av_write_trailer(ffmpeg_clean.format_context);
    
    open_success = false;
}

#pragma mark - private
- (int)p_start_rtmp
{
    char *rtmp_url = (char*)"rtmp://172.16.7.165:1935/zbcs/room";
    ffmpeg_clean.format_context = avformat_alloc_context();
    if (!ffmpeg_clean.format_context)
        return -1;
    
    if (avio_open(&ffmpeg_clean.io_context, rtmp_url, AVIO_FLAG_WRITE) < 0)
        return -1;
    
    ffmpeg_clean.format_context->pb = ffmpeg_clean.io_context;
    
    AVCodec *video_codec = avcodec_find_encoder(AV_CODEC_ID_H264);
    ffmpeg_clean.video_stream = avformat_new_stream(ffmpeg_clean.format_context, video_codec);
    if (!ffmpeg_clean.video_stream)
        return -1;
    
    if (!(ffmpeg_clean.format_context->oformat = av_guess_format("flv", rtmp_url, NULL)))
        return -1;
    
    ffmpeg_clean.video_stream->codec->bit_rate = 40000;
    ffmpeg_clean.video_stream->codec->width = 640;
    ffmpeg_clean.video_stream->codec->height = 368;
    ffmpeg_clean.video_stream->codec->gop_size = 30;
    ffmpeg_clean.video_stream->codec->pix_fmt = AV_PIX_FMT_YUV420P;
    ffmpeg_clean.video_stream->codec->time_base.den = 30;
    ffmpeg_clean.video_stream->codec->time_base.num = 1;
    // ffmpeg_clean.video_stream->codec->codec_tag = 0;
    
    // 有Codec for stream 0 does not use global headers but container format requires global headers警告
    // https://blog.csdn.net/passionkk/article/details/75528653说AVCondeContext的flags设置为AV_CODEC_FLAG_GLOBAL_HEADER会导致x264的b_repeat_header为0 这样每个I帧前都不会有sps跟pps 这里我们开启该功能否则有警告
    if (ffmpeg_clean.format_context->oformat->flags & AVFMT_GLOBALHEADER)
        ffmpeg_clean.video_stream->codec->flags |= CODEC_FLAG_GLOBAL_HEADER;
    
    // 这里因为调试方便自己写死了sps跟pps
//    static unsigned char sps_pps[] = {0x00, 0x00, 0x00, 0x01, 0x27, 0x64,  0x00, 0x1E, 0xAC, 0x56, 0xC1, 0x70, 0x51, 0xA6, 0xA0, 0x20, 0x20, 0x20, 0x40, 0x00, 0x00, 0x00, 0x01, 0x28, 0xEE, 0x3C, 0xB0};
    static unsigned char sps_pps[] = {0x00, 0x00, 0x00, 0x01, 0x67, 0x64, 0x00, 0x1E, 0xAC, 0xD9, 0x40, 0xA0, 0x2D, 0xA1, 0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x00, 0x03, 0x00, 0x32, 0x0F, 0x16, 0x2D, 0x96, 0x00, 0x00, 0x00, 0x01, 0x68, 0xEB, 0xE3, 0xCB, 0x22, 0xC0};
    
    ffmpeg_clean.video_stream->codec->extradata = sps_pps;
    ffmpeg_clean.video_stream->codec->extradata_size = sizeof(sps_pps);
    
    ffmpeg_clean.format_context->max_interleave_delta = 1000000;
    if (avformat_write_header(ffmpeg_clean.format_context, NULL) < 0)
        return -1;
    
    open_success = true;
    return 0;
}

static char start_code[4] = {0x00, 0x00, 0x00, 0x01};
- (void)push_rtmp:(const char *)buffer size:(const int)size
{
    if (!open_success || memcmp(buffer, start_code, 4) != 0)
        return;
    
    int naltype = buffer[4] & 0x1F;
    if (naltype != 0x01 && naltype != 0x05)
        return;
    
    AVPacket pkt = {0};
    pkt.data = (uint8_t*)buffer;
    pkt.size = size;
    pkt.stream_index = ffmpeg_clean.video_stream->index;
    if (naltype == 0x05)
        pkt.flags = AV_PKT_FLAG_KEY;
    
    static unsigned int video_count = 0;
    pkt.duration = (int)av_rescale_q(1, ffmpeg_clean.video_stream->codec->time_base, ffmpeg_clean.video_stream->time_base);
    pkt.pts = pkt.dts = video_count++*pkt.duration;
    
    int ret = av_interleaved_write_frame(ffmpeg_clean.format_context, &pkt);
    if (ret != 0)
    {
        NSLog(@"zz av_interleaved_write_frame : %d", ret);
        NSLog(@"zz %s", av_err2str(ret));
    }
}

#pragma mark - dealloc
- (void)dealloc
{
    stop = true;
    thread.join();
}
@end
