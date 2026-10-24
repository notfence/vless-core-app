#include "../common/flag_logic.h"
#include "check.h"
#include <time.h>

static size_t encode(uint32_t cp, uint16_t *out) {
    if (cp <= 0xffff) { out[0]=(uint16_t)cp; return 1; }
    cp-=0x10000; out[0]=(uint16_t)(0xd800+(cp>>10)); out[1]=(uint16_t)(0xdc00+(cp&1023)); return 2;
}

static void expect(const uint32_t *values, size_t count, size_t flags) {
    uint16_t text[256]; size_t length=0, cursor=0, found=0;
    for (size_t i=0;i<count;i++) length+=encode(values[i],text+length);
    VCFlagMatch match;
    while (VCFlagNext(text,length,&cursor,&match)) {
        CHECK("flags/match-bounds",match.length && match.location+match.length<=length && cursor==match.location+match.length);
        found++;
    }
    CHECK("flags/count",found==flags && cursor==length);
}

int main(int argc, char **argv) {
    size_t unique=0;
    for (size_t i=0;i<VCFlagSequenceCount();i++) {
        const VCFlagSequence *sequence=VCFlagSequenceAt(i);
        uint16_t text[32]; size_t n=0, cursor=0; VCFlagMatch match;
        for (size_t j=0;j<sequence->count;j++) n+=encode(sequence->codepoints[j],text+n);
        CHECK("flags/all-sequences",VCFlagNext(text,n,&cursor,&match) && match.location==0 && match.length==n && !strcmp(match.asset,sequence->asset));
        CHECK("flags/no-duplicate",!VCFlagNext(text,n,&cursor,&match));
        int first=1;
        for (size_t j=0;j<i;j++) if (!strcmp(sequence->asset,VCFlagSequenceAt(j)->asset)) first=0;
        unique+=first;
    }
    CHECK("flags/268-images",unique==268);
    const uint32_t text[]={'N','L',' ', '[','U','S',']',0x420,0x1f600,0xd800}; expect(text,10,0);
    const uint32_t adjacent[]={0x1f1f3,0x1f1f1,0x1f1fa,0x1f1f8,0x1f1e6}; expect(adjacent,5,2);
    const uint32_t parity[]={0x1f1e6,0x1f1e6,0x1f1f3,0x1f1f1}; expect(parity,4,1);
    const uint32_t shifted[]={0x1f1e6,0x1f1f3,0x1f1f1}; expect(shifted,3,0);
    const uint32_t pirate[]={0x1f3f4,0x200d,0x2620,0xfe0f}; expect(pirate,4,1);
    const uint32_t unbundled[][5]={
        {0x1f3f3,0xfe0f,0x200d,0x1f308},
        {0x1f3f3,0x200d,0x1f308},
        {0x1f3f3,0xfe0f,0x200d,0x26a7,0xfe0f},
        {0x1f3f3,0x200d,0x26a7,0xfe0f},
        {0x1f3f3,0xfe0f,0x200d,0x26a7},
        {0x1f3f3,0x200d,0x26a7}
    };
    const size_t unbundledLengths[]={4,3,5,4,4,3};
    for (size_t i=0;i<sizeof(unbundledLengths)/sizeof(unbundledLengths[0]);i++) expect(unbundled[i],unbundledLengths[i],0);
    const uint32_t mixed[]={0x1f3f3,0xfe0f,' ',0x1f3f3,0xfe0f,0x200d,0x1f308,' ',0x1f1f3,0x1f1f1}; expect(mixed,10,2);
    const uint32_t unknown[]={0x1f3f4,0xe0061,0xe007f,'x',0x1f3f3,0x200d,0x1f600}; expect(unknown,7,0);
    const uint32_t broken[]={0x1f3f4,0xe0067,0xe0062,0x1f3f3,0x200d}; expect(broken,5,0);
    const uint32_t textStyle[]={0x1f3f3,0xfe0e}; expect(textStyle,2,0);
    const uint32_t embeddedUnknown[]={0x1f600,0x200d,0x1f3f4}; expect(embeddedUnknown,3,0);
    const uint32_t unknownZWJ[]={0x1f3f4,0x200d,0x2620,0xfe0f,0x200d,0x1f600}; expect(unknownZWJ,6,0);
    const uint32_t doubledVS[]={0x1f3f3,0xfe0f,0xfe0f}; expect(doubledVS,3,0);
    const uint32_t middle[]={0x5d0,' ',0x1f1f3,0x1f1f1,' ',0x5d1}; expect(middle,6,1);
    CHECK("flags/null",!VCFlagNext(NULL,0,NULL,NULL));
    unsigned state=91;
    for (size_t round=0;round<50000;round++) {
        uint16_t data[96]; size_t size=round%96, cursor=0, previous=0; VCFlagMatch match;
        for (size_t j=0;j<size;j++) { state=state*1664525u+1013904223u; data[j]=(uint16_t)(state>>8); }
        if (size>16 && round%3==0) { data[4]=0xd83c; data[5]=0xddf3; data[6]=0xd83c; data[7]=0xddf1; }
        uint16_t saved[96]; memcpy(saved,data,size*sizeof(*data));
        while (VCFlagNext(data,size,&cursor,&match)) {
            CHECK("flags/fuzz-progress",cursor>previous && cursor<=size && match.location>=previous);
            previous=cursor;
        }
        CHECK("flags/fuzz-finished",cursor==size);
        CHECK("flags/fuzz-source-unchanged",!memcmp(saved,data,size*sizeof(*data)));
    }
    if (argc>1 && !strcmp(argv[1],"--measure")) {
        const size_t counts[]={1000,6000,20000};
        uint16_t name[]={'N','L',' ',0xd83c,0xddf3,0xd83c,0xddf1,' ',0x420,0x443};
        for (size_t i=0;i<3;i++) {
            clock_t started=clock(); size_t found=0;
            for (size_t j=0;j<counts[i];j++) { size_t cursor=0; VCFlagMatch match; while (VCFlagNext(name,10,&cursor,&match)) found++; }
            printf("MEASURE %zu %.6f %zu\n",counts[i],(double)(clock()-started)/CLOCKS_PER_SEC,found);
        }
    }
    FINISH("flags");
    return 0;
}
