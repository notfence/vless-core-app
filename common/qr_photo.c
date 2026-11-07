#include "qr_photo.h"
#include <zbar.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

static void clear_bytes(void *data,size_t size) { volatile uint8_t *p=data; while (size--) *p++=0; }
void VCQRPhotoResultClear(VCQRPhotoResult *result) {
    if (!result) return;
    for (size_t i=0;i<result->count;i++) { clear_bytes(result->entries[i].text,result->entries[i].length); free(result->entries[i].text); }
    free(result->entries); result->entries=NULL; result->count=0;
}
static int order(const void *a,const void *b) {
    const VCQRPhotoEntry *left=a,*right=b;
    if (left->y != right->y) return left->y < right->y ? -1 : 1;
    return left->x < right->x ? -1 : left->x > right->x;
}
static int prepare_pixels(const uint8_t *source,size_t width,size_t height,size_t stride,size_t scale,unsigned rotated,uint8_t *pixels,VCQRPhotoCancellation cancel,void *context) {
    size_t scanWidth=(width+scale-1)/scale,scanHeight=(height+scale-1)/scale;
    for (size_t y=0;y<height;y+=scale) {
        if (cancel && cancel(context)) return 0;
        if (scale==1) {
            if (!rotated) memcpy(pixels+y*width,source+y*stride,width);
            else for (size_t x=0;x<width;x++) pixels[x*height+height-1-y]=source[y*stride+x];
            continue;
        }
        size_t rows=height-y<scale ? height-y : scale;
        for (size_t x=0;x<width;x+=scale) {
            size_t columns=width-x<scale ? width-x : scale;
            unsigned sum=0;
            for (size_t dy=0;dy<rows;dy++) for (size_t dx=0;dx<columns;dx++) sum+=source[(y+dy)*stride+x+dx];
            size_t offset=rotated ? (x/scale)*scanHeight+scanHeight-1-y/scale : (y/scale)*scanWidth+x/scale;
            pixels[offset]=(uint8_t)(sum/(rows*columns));
        }
    }
    return 1;
}
VCQRPhotoStatus VCQRPhotoDecode(const uint8_t *source,size_t width,size_t height,size_t stride,VCQRPhotoCancellation cancel,void *context,VCQRPhotoResult *result) {
    if (!result) return VCQRPhotoInvalid;
    result->entries=NULL; result->count=0;
    if (!source || !width || !height || width>2048 || height>2048 || stride<width || stride>SIZE_MAX/height) return VCQRPhotoInvalid;
    if (cancel && cancel(context)) return VCQRPhotoCancelled;
    size_t length=width*height,total=0;
    uint8_t *pixels=malloc(length);
    zbar_image_scanner_t *scanner=zbar_image_scanner_create();
    zbar_image_t *image=zbar_image_create();
    VCQRPhotoStatus status=VCQRPhotoMemory;
    if (!pixels || !scanner || !image) goto done;
    zbar_image_scanner_enable_cache(scanner,0);
    zbar_image_scanner_set_config(scanner,ZBAR_NONE,ZBAR_CFG_ENABLE,0);
    zbar_image_scanner_set_config(scanner,ZBAR_QRCODE,ZBAR_CFG_ENABLE,1);
    zbar_image_set_format(image,zbar_fourcc('Y','8','0','0'));
    status=VCQRPhotoEmpty;
    for (unsigned rotated=0;rotated<2;rotated++) for (size_t scale=1;;scale*=2) {
        size_t sourceWidth=(width+scale-1)/scale,sourceHeight=(height+scale-1)/scale;
        size_t scanWidth=rotated ? sourceHeight : sourceWidth,scanHeight=rotated ? sourceWidth : sourceHeight;
        if (!prepare_pixels(source,width,height,stride,scale,rotated,pixels,cancel,context)) { status=VCQRPhotoCancelled; goto done; }
        zbar_image_set_size(image,(unsigned)scanWidth,(unsigned)scanHeight);
        zbar_image_set_data(image,pixels,scanWidth*scanHeight,NULL);
        for (unsigned pass=0;pass<2;pass++) {
            if (cancel && cancel(context)) { status=VCQRPhotoCancelled; goto done; }
            if (pass) for (size_t y=0;y<scanHeight;y++) {
                if (cancel && cancel(context)) { status=VCQRPhotoCancelled; goto done; }
                for (size_t x=0;x<scanWidth;x++) pixels[y*scanWidth+x]=255-pixels[y*scanWidth+x];
            }
            if (zbar_scan_image(scanner,image)<0) { status=VCQRPhotoInvalid; goto done; }
            if (cancel && cancel(context)) { status=VCQRPhotoCancelled; goto done; }
            for (const zbar_symbol_t *symbol=zbar_image_first_symbol(image);symbol;symbol=zbar_symbol_next(symbol)) {
                if (cancel && cancel(context)) { status=VCQRPhotoCancelled; goto done; }
                if (zbar_symbol_get_type(symbol)!=ZBAR_QRCODE) continue;
                const char *text=zbar_symbol_get_data(symbol); size_t size=zbar_symbol_get_data_length(symbol);
                if (!text || !size) continue;
                if (size>32U*1024U*1024U-total) { status=VCQRPhotoInvalid; goto done; }
                int x=INT_MAX,y=INT_MAX;
                for (unsigned i=0;i<zbar_symbol_get_loc_size(symbol);i++) {
                    int px=zbar_symbol_get_loc_x(symbol,i),py=zbar_symbol_get_loc_y(symbol,i);
                    if (px<0 || py<0 || (size_t)px>=scanWidth || (size_t)py>=scanHeight) continue;
                    int ox=(int)((rotated ? (size_t)py : (size_t)px)*scale);
                    int oy=(int)((rotated ? sourceHeight-1-(size_t)px : (size_t)py)*scale);
                    if (ox<x) x=ox; if (oy<y) y=oy;
                }
                size_t found=0;
                while (found<result->count && (result->entries[found].length!=size || memcmp(result->entries[found].text,text,size))) found++;
                if (found<result->count) {
                    VCQRPhotoEntry *entry=&result->entries[found];
                    if (y<entry->y || (y==entry->y && x<entry->x)) { entry->x=x; entry->y=y; }
                    continue;
                }
                if (result->count >= SIZE_MAX/sizeof(VCQRPhotoEntry)-1) { status=VCQRPhotoMemory; goto done; }
                VCQRPhotoEntry *entries=realloc(result->entries,(result->count+1)*sizeof(*entries));
                if (!entries) { status=VCQRPhotoMemory; goto done; }
                result->entries=entries;
                char *copy=malloc(size+1);
                if (!copy) { status=VCQRPhotoMemory; goto done; }
                memcpy(copy,text,size); copy[size]=0;
                entries[result->count++]=(VCQRPhotoEntry){copy,size,x,y}; total+=size;
            }
        }
        if (scanWidth<=512 && scanHeight<=512) break;
    }
    if (result->count) { qsort(result->entries,result->count,sizeof(*result->entries),order); status=VCQRPhotoOK; }
done:
    if (image) { zbar_image_set_data(image,NULL,0,NULL); zbar_image_destroy(image); }
    if (scanner) zbar_image_scanner_destroy(scanner);
    if (pixels) { clear_bytes(pixels,length); free(pixels); }
    if (status!=VCQRPhotoOK) VCQRPhotoResultClear(result);
    return status;
}
