#include "flag_logic.h"
#include "flag_data.h"

size_t VCFlagSequenceCount(void) { return sizeof(sequences)/sizeof(sequences[0]); }
const VCFlagSequence *VCFlagSequenceAt(size_t index) { return index<VCFlagSequenceCount() ? sequences+index : NULL; }

static uint32_t scalar(const uint16_t *text, size_t length, size_t *cursor) {
    uint32_t value=text[(*cursor)++];
    if (value>=0xd800 && value<=0xdbff && *cursor<length && text[*cursor]>=0xdc00 && text[*cursor]<=0xdfff) {
        value=0x10000+((value-0xd800)<<10)+(text[(*cursor)++]-0xdc00);
    }
    return value;
}

static const char *lookup(const uint32_t *values, size_t count) {
    uint32_t first=values[0];
    if (!((first>=0x1f1e6 && first<=0x1f1ff) || first==0x1f38c || first==0x1f3c1 || first==0x1f3f3 || first==0x1f3f4 || first==0x1f6a9)) return NULL;
    size_t lo=0, hi=VCFlagSequenceCount();
    while (lo<hi) {
        size_t mid=lo+(hi-lo)/2; const VCFlagSequence *item=sequences+mid;
        size_t n=count<item->count ? count : item->count; int order=0;
        for (size_t i=0;i<n && !order;i++) order=values[i]<item->codepoints[i] ? -1 : values[i]>item->codepoints[i];
        if (!order) order=count<item->count ? -1 : count>item->count;
        if (!order) return item->asset;
        if (order<0) hi=mid; else lo=mid+1;
    }
    return NULL;
}

static int regional(uint32_t value) { return value>=0x1f1e6 && value<=0x1f1ff; }

int VCFlagNext(const uint16_t *text, size_t length, size_t *cursor, VCFlagMatch *match) {
    if (!cursor || !match || (!text && length) || *cursor>length) return 0;
    size_t p=*cursor;
    while (p<length) {
        size_t start=p, count=1; uint32_t values[8]; values[0]=scalar(text,length,&p);
        if (regional(values[0])) {
            size_t next=p;
            if (next<length) {
                uint32_t second=scalar(text,length,&next);
                if (regional(second)) { values[count++]=second; p=next; }
            }
        } else {
            while (p<length) {
                size_t next=p; uint32_t value=scalar(text,length,&next);
                if (value!=0xfe0f && value!=0xfe0e && value!=0x200d && !(value>=0xe0020 && value<=0xe007f)) break;
                if (count<8) values[count]=value;
                count++; p=next;
                if (value==0x200d && p<length) {
                    value=scalar(text,length,&p);
                    if (count<8) values[count]=value;
                    count++;
                }
            }
        }
        const char *asset=count<=8 ? lookup(values,count) : NULL;
        if (asset) {
            match->location=start; match->length=p-start; match->asset=asset; *cursor=p; return 1;
        }
    }
    *cursor=length; return 0;
}
