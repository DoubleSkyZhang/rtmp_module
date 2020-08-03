//
//  doublesky_rtmp.cpp
//  rtmp_module
//
//  Created by zz on 2020/7/26.
//  Copyright © 2020 zz. All rights reserved.
//

#include "doublesky_rtmp.hpp"

#include <iostream>

doublesky_rtmp::doublesky_rtmp()
{
    thread = std::thread(std::bind([this]
    {
        std::unique_lock<std::mutex> lock(mutex, std::defer_lock);
        while(!stop)
        {
            lock.lock();
            while(queue.empty())
                cond.wait(lock);
            
            // 推流
            this->push_rtmp(std::get<1>(queue.front()).get(), std::get<0>(queue.front()));
            queue.pop();
            lock.unlock();
        }
    }));
}

// ffmpeg -re -i /Users/zz/Downloads/RPReplay_Final1585299840.MP4 -vcodec copy -f flv rtmp://localhost:1935/zbcs/room
void doublesky_rtmp::push_buffer(char *buffer, int size, bool is_video)
{
    std::unique_lock<std::mutex> lock(mutex);
    std::shared_ptr<char> ptr(new char[size], std::default_delete<char[]>());
    memcpy(ptr.get(), buffer, size);
    queue.push(std::tuple<int, std::shared_ptr<char>, bool>(size, ptr, is_video));
    lock.unlock();
    cond.notify_one();
}

int doublesky_rtmp::start_rtmp()
{
    int ret = p_start_rtmp();
    if (ret != 0)
        ffmpeg_clean.clean();
    
    return ret;
}

void doublesky_rtmp::stop_rtmp()
{
    std::unique_lock<std::mutex> lock;
    std::queue<std::tuple<int, std::shared_ptr<char>, bool>> empty;
    std::swap(empty, queue);
    if (open_success)
        av_write_trailer(ffmpeg_clean.format_context);
    
    ffmpeg_clean.clean();
    open_success = false;
}

int doublesky_rtmp::p_start_rtmp()
{
    // rtmp://172.16.7.229:1935/zbcs/room
    char *rtmp_url = (char*)"rtmp://108588.livepush.myqcloud.com/live/doublesky?txSecret=79819f780871f153514b80395b2633db&txTime=5F4CD6CC";
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
    
//    AVCodec *audio_codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
//    ffmpeg_clean.video_stream = avformat_new_stream(ffmpeg_clean.format_context, audio_codec);
//    if (!ffmpeg_clean.audio_stream)
//        return -1;
    
    if (!(ffmpeg_clean.format_context->oformat = av_guess_format("flv", rtmp_url, NULL)))
        return -1;
    
    ffmpeg_clean.video_stream->codec->bit_rate = 40000;
    ffmpeg_clean.video_stream->codec->width = 640;
    ffmpeg_clean.video_stream->codec->height = 352;
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
    static unsigned char sps_pps[] = {0x00, 0x00, 0x00, 0x01, 0x67, 0x64, 0x00, 0x1E, 0xAC, 0xB2, 0x01, 0x40, 0x5B, 0x42, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00, 0x64, 0x1E, 0x2C, 0x5C, 0x90, 0x00, 0x00, 0x00, 0x01, 0x68, 0xEB, 0xC3, 0xCB, 0x22, 0xC0};
    char *tmp_sps_pps = (char*)calloc(1, sizeof(sps_pps));
    memcpy(tmp_sps_pps, sps_pps, sizeof(sps_pps));
    ffmpeg_clean.video_stream->codec->extradata = (uint8_t*)tmp_sps_pps;
    ffmpeg_clean.video_stream->codec->extradata_size = sizeof(sps_pps);
    
    ffmpeg_clean.format_context->max_interleave_delta = 1000000;
    if (avformat_write_header(ffmpeg_clean.format_context, NULL) < 0)
        return -1;
    
    open_success = true;
    return 0;
}

static char start_code_3[3] = {0x00, 0x00, 0x01};
static char start_code_4[4] = {0x00, 0x00, 0x00, 0x01};
void doublesky_rtmp::push_rtmp(const char *buffer, const int size)
{
    if (!open_success)
        return;
    
    int start_length = 0;
    if (memcmp(buffer, start_code_3, 3) == 0)
        start_length = 3;
    
    if (memcmp(buffer, start_code_4, 4) == 0)
        start_length = 4;
    
    if (start_length == 0)
        return;
    
    int naltype = buffer[start_length] & 0x1F;
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
        std::cout << "zz av_interleaved_write_frame : %d" << ret << std::endl;
        std::cout << "zz %s" << av_err2str(ret) << std::endl;
    }
}

doublesky_rtmp::~doublesky_rtmp()
{
    stop = true;
    thread.join();
}
