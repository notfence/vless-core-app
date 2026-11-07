#include "check.h"
#include "../common/qr_photo.h"
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>
#include <zbar.h>

static int failAt=-1,allocations;
static int allocationFails(void) { return failAt>=0 && allocations++==failAt; }
static void *photoMalloc(size_t n) { return allocationFails() ? NULL : malloc(n); }
static void *photoRealloc(void *p,size_t n) { return allocationFails() ? NULL : realloc(p,n); }
static zbar_image_t *photoImage(void) { return allocationFails() ? NULL : zbar_image_create(); }
static zbar_image_scanner_t *photoScanner(void) { return allocationFails() ? NULL : zbar_image_scanner_create(); }
static unsigned scanCalls,fullSizeSymbols;
static int photoScan(zbar_image_scanner_t *scanner,zbar_image_t *image) {
    int count=zbar_scan_image(scanner,image);
    if (scanCalls++<2 && count>0) fullSizeSymbols+=(unsigned)count;
    return count;
}
#define malloc photoMalloc
#define realloc photoRealloc
#define zbar_image_create photoImage
#define zbar_image_scanner_create photoScanner
#define zbar_scan_image photoScan
#include "../common/qr_photo.c"
#undef malloc
#undef realloc
#undef zbar_image_create
#undef zbar_image_scanner_create
#undef zbar_scan_image

static int cancelled(void *context) { return ++*(unsigned *)context >= 2; }
static int cancelAfterScan(void *context) { return scanCalls>=*(unsigned *)context; }
static long memoryKiB(const char *field) {
    FILE *file=fopen("/proc/self/status","r"); if (!file) return -1;
    char line[256]; long value=-1;
    while (fgets(line,sizeof(line),file)) if (!strncmp(line,field,strlen(field))) { value=strtol(line+strlen(field),NULL,10); break; }
    fclose(file); return value;
}
int main(int argc,char **argv) {
    FILE *file=fopen("qr_fixture.txt","r"); CHECK("photo/fixture",file != NULL);
    char matrix[128][130]; unsigned side=0;
    while (side < 128 && fgets(matrix[side],sizeof(matrix[side]),file)) side++;
    fclose(file);
    unsigned size=side*6,width=size*2+32,height=size+32;
    uint8_t *pixels=malloc((size_t)width*height); CHECK("photo/allocation",pixels != NULL);
    memset(pixels,255,(size_t)width*height);
    for (unsigned y=0;y<size;y++) for (unsigned x=0;x<size;x++) {
        uint8_t value=matrix[y/6][x/6]=='1' ? 0 : 255;
        pixels[(y+16)*width+x+8]=value;
        pixels[(y+16)*width+x+size+24]=value;
    }
    VCQRPhotoResult result={0};
    CHECK("photo/decode",VCQRPhotoDecode(pixels,width,height,width,NULL,NULL,&result)==VCQRPhotoOK);
    CHECK("photo/deduplicated",result.count==1);
    CHECK("photo/payload",result.count && !strcmp(result.entries[0].text,"socks5://127.0.0.1:1080#vless-core"));
    VCQRPhotoResultClear(&result);
    for (unsigned i=0;i<width*height;i++) pixels[i]=255-pixels[i];
    CHECK("photo/inverted",VCQRPhotoDecode(pixels,width,height,width,NULL,NULL,&result)==VCQRPhotoOK && result.count==1);
    VCQRPhotoResultClear(&result);
    unsigned calls=0;
    CHECK("photo/cancel",VCQRPhotoDecode(pixels,width,height,width,cancelled,&calls,&result)==VCQRPhotoCancelled && !result.count);
    CHECK("photo/oversized",VCQRPhotoDecode(pixels,2049,1,2049,NULL,NULL,&result)==VCQRPhotoInvalid);
    CHECK("photo/stride",VCQRPhotoDecode(pixels,width,height,width-1,NULL,NULL,&result)==VCQRPhotoInvalid);
    CHECK("photo/null",VCQRPhotoDecode(NULL,width,height,width,NULL,NULL,&result)==VCQRPhotoInvalid);
    memset(pixels,255,(size_t)width*height);
    CHECK("photo/no-qr",VCQRPhotoDecode(pixels,width,height,width,NULL,NULL,&result)==VCQRPhotoEmpty);
    CHECK("photo/no-retained-results",!result.entries && !result.count);
    file=fopen("qr_photo_fixture.txt","r"); CHECK("photo/second-fixture",file!=NULL);
    char second[128][130]; unsigned secondSide=0;
    while (secondSide<128 && fgets(second[secondSide],sizeof(second[secondSide]),file)) secondSide++;
    fclose(file);
    for (unsigned y=0;y<size;y++) for (unsigned x=0;x<size;x++) pixels[(y+16)*width+x+8]=matrix[y/6][x/6]=='1' ? 0 : 255;
    for (unsigned y=0;y<secondSide*6;y++) for (unsigned x=0;x<secondSide*6;x++) pixels[(y+16)*width+x+size+24]=second[y/6][x/6]=='1' ? 0 : 255;
    CHECK("photo/two-different-codes",VCQRPhotoDecode(pixels,width,height,width,NULL,NULL,&result)==VCQRPhotoOK && result.count==2);
    CHECK("photo/reading-order",result.count==2 && !strcmp(result.entries[0].text,"socks5://127.0.0.1:1080#vless-core") && !strcmp(result.entries[1].text,"https://second.test/sub?a=b+c%25"));
    VCQRPhotoResultClear(&result);
    for (int fault=0;fault<7;fault++) {
        failAt=fault; allocations=0;
        CHECK("photo/allocation-failure",VCQRPhotoDecode(pixels,width,height,width,NULL,NULL,&result)==VCQRPhotoMemory && !result.count && !result.entries);
    }
    failAt=-1;
    uint8_t *transformed=malloc((size_t)width*height); CHECK("photo/transform-buffer",transformed!=NULL);
    for (unsigned turn=0;turn<4;turn++) for (unsigned mirror=0;mirror<2;mirror++) {
        unsigned tw=turn&1 ? height : width,th=turn&1 ? width : height;
        for (unsigned y=0;y<height;y++) for (unsigned x=0;x<width;x++) {
            unsigned tx=turn==0 ? x : turn==1 ? height-1-y : turn==2 ? width-1-x : y;
            unsigned ty=turn==0 ? y : turn==1 ? x : turn==2 ? height-1-y : width-1-x;
            if (mirror) tx=tw-1-tx;
            transformed[ty*tw+tx]=pixels[y*width+x];
        }
        CHECK("photo/rotation-and-mirror",VCQRPhotoDecode(transformed,tw,th,tw,NULL,NULL,&result)==VCQRPhotoOK && result.count==2);
        VCQRPhotoResultClear(&result);
    }
    free(transformed);
    unsigned photoWidth=1537,photoHeight=2047,photoStride=1541;
    uint8_t *photograph=malloc((size_t)photoStride*photoHeight);
    CHECK("photo/multiscale-buffer",photograph!=NULL);
    for (unsigned y=0;y<photoHeight;y++) for (unsigned x=0;x<photoStride;x++) {
        int value=6;
        if (x>=160 && x<160+side*32 && y>=400 && y<400+side*32 && matrix[(y-400)/32][(x-160)/32]=='1') value=100;
        value+=((x+y)&1) ? 8 : -8;
        photograph[(size_t)y*photoStride+x]=(uint8_t)(value<0 ? 0 : value);
    }
    scanCalls=fullSizeSymbols=0;
    CHECK("photo/large-textured-inverted-code",VCQRPhotoDecode(photograph,photoWidth,photoHeight,photoStride,NULL,NULL,&result)==VCQRPhotoOK && result.count==1);
    CHECK("photo/bounded-multiscale-passes",scanCalls==12 && !fullSizeSymbols);
    CHECK("photo/multiscale-original-payload",result.count==1 && !strcmp(result.entries[0].text,"socks5://127.0.0.1:1080#vless-core"));
    CHECK("photo/multiscale-original-coordinates",result.entries[0].x>=160 && result.entries[0].x<160+(int)side*32 && result.entries[0].y>=400 && result.entries[0].y<400+(int)side*32);
    VCQRPhotoResultClear(&result);
    for (unsigned y=0;y<secondSide*3;y++) for (unsigned x=0;x<secondSide*3;x++)
        photograph[(size_t)(y+16)*photoStride+x+16]=second[y/3][x/3]=='1' ? 0 : 255;
    scanCalls=fullSizeSymbols=0;
    CHECK("photo/multiple-scales-merged",VCQRPhotoDecode(photograph,photoWidth,photoHeight,photoStride,NULL,NULL,&result)==VCQRPhotoOK && result.count==2);
    CHECK("photo/full-size-success-still-searches-scales",fullSizeSymbols==1 && scanCalls==12);
    CHECK("photo/multiscale-reading-order",result.count==2 && !strcmp(result.entries[0].text,"https://second.test/sub?a=b+c%25") && !strcmp(result.entries[1].text,"socks5://127.0.0.1:1080#vless-core"));
    VCQRPhotoResultClear(&result);
    for (unsigned after=1;after<=12;after++) {
        scanCalls=0;
        CHECK("photo/cancel-between-scale-passes",VCQRPhotoDecode(photograph,photoWidth,photoHeight,photoStride,cancelAfterScan,&after,&result)==VCQRPhotoCancelled && !result.count && !result.entries && scanCalls==after);
    }
    free(photograph);
    file=fopen("qr_photo_dense_fixture.txt","r"); CHECK("photo/dense-fixture",file!=NULL);
    char dense[128][130]; unsigned denseSide=0;
    while (denseSide<128 && fgets(dense[denseSide],sizeof(dense[denseSide]),file)) denseSide++;
    fclose(file); CHECK("photo/dense-matrix",denseSide==81 && strcspn(dense[0],"\r\n")==denseSide);
    unsigned denseWidth=1200,denseHeight=1600;
    uint8_t *sharp=malloc((size_t)denseWidth*denseHeight),*blurred=malloc((size_t)denseWidth*denseHeight);
    CHECK("photo/dense-buffers",sharp && blurred);
    for (unsigned y=0;y<denseHeight;y++) for (unsigned x=0;x<denseWidth;x++) {
        unsigned offset=y>=400 ? 150+(y-400)*4/100 : denseWidth;
        sharp[(size_t)y*denseWidth+x]=y>=400 && (y-400)/6<denseSide && x>=offset && (x-offset)/6<denseSide && dense[(y-400)/6][(x-offset)/6]=='1' ? 40 : 210;
    }
    for (unsigned y=0;y<denseHeight;y++) for (unsigned x=0;x<denseWidth;x++) {
        unsigned sum=0;
        for (int dy=-2;dy<=2;dy++) for (int dx=-2;dx<=2;dx++) {
            int sx=(int)x+dx,sy=(int)y+dy;
            if (sx<0) sx=0; if (sx>=(int)denseWidth) sx=(int)denseWidth-1;
            if (sy<0) sy=0; if (sy>=(int)denseHeight) sy=(int)denseHeight-1;
            sum+=sharp[(size_t)sy*denseWidth+(unsigned)sx];
        }
        blurred[(size_t)(denseWidth-1-x)*denseHeight+y]=(uint8_t)(sum/25);
    }
    free(sharp); scanCalls=fullSizeSymbols=0;
    CHECK("photo/dense-orientation-fallback",VCQRPhotoDecode(blurred,denseHeight,denseWidth,denseHeight,NULL,NULL,&result)==VCQRPhotoOK && result.count==1);
    CHECK("photo/bounded-orientation-passes",scanCalls==12 && !fullSizeSymbols);
    char expected[512]="https://dense.test/sub?token=";
    for (unsigned i=0;i<10;i++) strcat(expected,"abcdefghijklmnopqrstuvwxyz0123456789");
    strcat(expected,"abcdefghijklmnopqr");
    CHECK("photo/dense-complete-payload",result.count==1 && result.entries[0].length==strlen(expected) && !strcmp(result.entries[0].text,expected));
    CHECK("photo/dense-original-coordinates",result.entries[0].x>=390 && result.entries[0].x<896 && result.entries[0].y>=500 && result.entries[0].y<1100);
    VCQRPhotoResultClear(&result); free(blurred);
    uint8_t *large=malloc(2048U*2048U); CHECK("photo/large-buffer",large!=NULL);
    memset(large,255,2048U*2048U);
    for (unsigned y=0;y<height;y++) memcpy(large+(size_t)y*2048,pixels+(size_t)y*width,width);
    CHECK("photo/maximum-working-image",VCQRPhotoDecode(large,2048,2048,2048,NULL,NULL,&result)==VCQRPhotoOK && result.count==2);
    VCQRPhotoResultClear(&result); free(large);
    uint32_t seed=7; uint8_t noise[96*96];
    for (unsigned i=0;i<200;i++) {
        for (unsigned j=0;j<sizeof(noise);j++) { seed=seed*1664525U+1013904223U; noise[j]=(uint8_t)(seed>>24); }
        VCQRPhotoStatus status=VCQRPhotoDecode(noise,96,96,96,NULL,NULL,&result);
        CHECK("photo/malformed-image-regression",status==VCQRPhotoEmpty || status==VCQRPhotoOK);
        VCQRPhotoResultClear(&result);
    }
    unsigned repeat=argc>1 ? (unsigned)strtoul(argv[1],NULL,10) : 1;
    if (argc>2 && !strcmp(argv[2],"large")) {
        uint8_t *expanded=malloc(2048U*2048U); CHECK("photo/benchmark-buffer",expanded!=NULL);
        memset(expanded,255,2048U*2048U);
        for (unsigned y=0;y<height;y++) memcpy(expanded+(size_t)y*2048,pixels+(size_t)y*width,width);
        free(pixels); pixels=expanded; width=height=2048;
    }
    struct timespec start,end; struct rusage initial,usage; getrusage(RUSAGE_SELF,&initial); clock_gettime(CLOCK_MONOTONIC,&start);
    for (unsigned i=0;i<repeat;i++) {
        CHECK("photo/repeated-read",VCQRPhotoDecode(pixels,width,height,width,NULL,NULL,&result)==VCQRPhotoOK && result.count==2);
        VCQRPhotoResultClear(&result);
    }
    clock_gettime(CLOCK_MONOTONIC,&end);
    getrusage(RUSAGE_SELF,&usage);
    free(pixels);
    printf("{\"iterations\":%u,\"width\":%u,\"height\":%u,\"elapsed_ms\":%.3f,\"cpu_ms\":%.3f,\"process_peak_rss_kib\":%ld,\"rss_after_kib\":%ld}\n",repeat,width,height,(end.tv_sec-start.tv_sec)*1000.0+(end.tv_nsec-start.tv_nsec)/1e6,
        (usage.ru_utime.tv_sec+usage.ru_stime.tv_sec-initial.ru_utime.tv_sec-initial.ru_stime.tv_sec)*1000.0+(usage.ru_utime.tv_usec+usage.ru_stime.tv_usec-initial.ru_utime.tv_usec-initial.ru_stime.tv_usec)/1000.0,memoryKiB("VmHWM:"),memoryKiB("VmRSS:"));
    FINISH("photo QR decoding"); return 0;
}
