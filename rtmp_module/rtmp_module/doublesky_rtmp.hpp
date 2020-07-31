//
//  doublesky_rtmp.hpp
//  rtmp_module
//
//  Created by zz on 2020/7/26.
//  Copyright © 2020 zz. All rights reserved.
//

#ifndef doublesky_rtmp_hpp
#define doublesky_rtmp_hpp

// .m文件中引入c++头文件会导致该头文件编译类型为oc 会报找不到c++系统库头文件错误
#include <stdio.h>
#include <tuple>
#include <memory>
#include <queue>
#include <thread>

extern "C"
{
    #include <libavformat/avformat.h>
}

class doublesky_ffmpeg_clean
{
public:
    doublesky_ffmpeg_clean() : format_context(NULL), io_context(NULL), video_stream(NULL), audio_stream(NULL)
    {
        av_register_all();
        avformat_network_init();
        //av_log_set_level(AV_LOG_DEBUG);
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

class doublesky_rtmp
{
public:
    doublesky_rtmp();
    ~doublesky_rtmp();
    void push_buffer(char *buffer, int size, bool is_video);
    int start_rtmp();
    void stop_rtmp();
    
private:
    std::queue<std::tuple<int, std::shared_ptr<char>, bool>> queue;
    std::thread thread;
    std::mutex mutex;
    std::condition_variable cond;
    bool stop, open_success;
    doublesky_ffmpeg_clean ffmpeg_clean;
    
    void push_rtmp(const char *buffer, const int size);
    int p_start_rtmp();
};
#endif /* doublesky_rtmp_hpp */
