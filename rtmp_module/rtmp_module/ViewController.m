//
//  ViewController.m
//  rtmp_module
//
//  Created by zz on 2020/7/26.
//  Copyright © 2020 zz. All rights reserved.
//

#import "ViewController.h"
#import "doublesky_rtmp_push.h"

@interface ViewController ()
{
    FILE *fp;
    NSThread *thread;
    bool push;
    doublesky_rtmp_push *rtmp;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    fp = fopen([[[NSBundle mainBundle] pathForResource:@"test.264" ofType:nil] UTF8String], "rb");
    assert(fp);
    
    UIWebView *web = [[UIWebView alloc] init];
    [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"www.baidu.com"]]];
    
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(100, 100, 200, 50)];
    [btn setTitle:@"开始推流" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(btn_click:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
    
    rtmp = [[doublesky_rtmp_push alloc] init];
}

- (void)btn_click:(UIButton *)tmp
{
    if (push)
    {
        push = false;
        [thread cancel];
        
        [rtmp stop_rtmp];
    }
    else
    {
        if ([rtmp start_rtmp] != 0)
            return;
        
        fseek(fp, 0, SEEK_SET);
        push = true;
        thread = [[NSThread alloc] initWithTarget:self selector:@selector(thread_start) object:nil];
        [thread start];
    }
    
    [tmp setTitle:push ? @"结束推流" : @"开始推流" forState:UIControlStateNormal];
}

- (void)thread_start
{
    while (push)
    {
        char *b = NULL;
        int size = [self getNalu:fp :&b];
        if (!b || size <= 0)
        {
            usleep(20*1000);
            continue;
        }
        
        // sps pps不能算进帧里
        static bool hasSps = false;
        if (size > 0)
        {
            if (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x00 && b[3] == 0x01 && ((b[4] & 0x1F) == 0x06))
                continue;
            
            if (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x00 && b[3] == 0x01 && ((b[4] & 0x1F) == 0x07))
            {
                if (hasSps)
                    continue;
                
                hasSps = true;
            }
        }
        
        [rtmp push_buffer:b size:size is_video:true];
        if (b) free(b);
        
        usleep(30*1000);
    }
}

#pragma mark - 模拟方法
// 文件为标准nalu文件读取方法
- (int)getNalu:(FILE *)fp :(char **)b {
    int size = -1;
    
    char *tmpBuffer = calloc(1024*500, sizeof(char));
    if (!tmpBuffer)
        return size;
    
    int begin = 0; // 第一个开始码的起始位置
    int current = 0;
    int cmpIndex = 0; // 从此处开始比对startcode的位置 因为需要读满四个字节再把该比对位置往后加 因此有++cmpIndex的判断
    int startCodeEnd = 0; // 第一个开始码的结束位置
    int startCodeSize = 0;
    while (fread(tmpBuffer+current, 1, 1, fp) > 0) {
        if (current-startCodeEnd > 3)
            ++cmpIndex;
        
        startCodeSize = 0;
        if (isStartCode1(tmpBuffer+cmpIndex) == YES) startCodeSize = 3;
        if (isStartCode2(tmpBuffer+cmpIndex) == YES) startCodeSize = 4;
        
        if (startCodeSize != 0) {
            if (startCodeEnd != 0) {
                // 结尾为001 current会往后多读一个字节
                if (startCodeSize == 4)
                    size = current-begin-startCodeSize+1;
                else
                    size = current-begin-startCodeSize;
                
                *b = calloc(size, sizeof(char));
                if (!(*b))
                    goto getNaluEnd;
                
                memcpy(*b, tmpBuffer+begin, size);
                fseek(fp, -4, SEEK_CUR);
                goto getNaluEnd;
            }else {
                begin = current-startCodeSize+1;
                ++current;
                cmpIndex = current;
                startCodeEnd = current;
                continue;
            }
        }
        
        ++current;
    }
    
getNaluEnd:
    if (tmpBuffer)
        free(tmpBuffer);
    
    return size;
}

static char startCode1[3] = {0, 0, 1};
bool isStartCode1(char *buffer) {
    if (memcmp(buffer, startCode1, 3) == 0)
        return YES;
    
    return NO;
}

static char startCode2[4] = {0, 0, 0, 1};
bool isStartCode2(char *buffer) {
    if (memcmp(buffer, startCode2, 4) == 0)
        return YES;
    
    return NO;
}
@end
