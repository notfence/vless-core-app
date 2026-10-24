#import "incy_links.h"
#import "../../common/app_constants.h"
#import "../../common/subscription_task.h"
#include "../../../vless-core-cli/include/json.h"
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <string.h>

BOOL VCIncyIsLink(NSString *text) {
    return [text isKindOfClass:[NSString class]] && [text rangeOfString:@"incy://" options:NSCaseInsensitiveSearch|NSAnchoredSearch].location == 0;
}

BOOL VCIncyIsCryptLink(NSString *text) {
    return VCIncyIsLink(text) && [text rangeOfString:@"incy://crypt1/" options:NSCaseInsensitiveSearch|NSAnchoredSearch].location == 0;
}

void VCIncyClearData(NSMutableData *data) {
    if ([data length]) OPENSSL_cleanse([data mutableBytes], [data length]);
}

NSMutableData *VCIncyDecodeBase64(NSString *text, BOOL urlOnly, NSUInteger maximum) {
    NSUInteger length=[text length],symbols=length,padding=0;
    if (!length || length > maximum) return nil;
    while (symbols && [text characterAtIndex:symbols-1] == '=') symbols--,padding++;
    if (!symbols || padding > 2 || symbols%4 == 1 || (padding && (length%4 || padding != (4-symbols%4)%4))) return nil;
    NSMutableData *result=[NSMutableData dataWithLength:symbols*3/4];
    unsigned char *output=[result mutableBytes]; NSUInteger position=0;
    unsigned value=0,bits=0,alphabet=0;
    for (NSUInteger i=0;i<symbols;i++) {
        if (!(i%4096) && VCCurrentSubscriptionTask().isCancelled) goto invalid;
        unichar c=[text characterAtIndex:i]; unsigned digit;
        if (c >= 'A' && c <= 'Z') digit=c-'A';
        else if (c >= 'a' && c <= 'z') digit=c-'a'+26;
        else if (c >= '0' && c <= '9') digit=c-'0'+52;
        else if (c == '+' || c == '/') { if (urlOnly) goto invalid; alphabet|=1; digit=c == '+' ? 62 : 63; }
        else if (c == '-' || c == '_') { alphabet|=2; digit=c == '-' ? 62 : 63; }
        else goto invalid;
        if (alphabet == 3) goto invalid;
        value=(value<<6)|digit; bits+=6;
        if (bits >= 8) { bits-=8; output[position++]=(unsigned char)(value>>bits); }
        value&=(1U<<bits)-1;
    }
    if (!value) return result;
invalid:
    VCIncyClearData(result);
    return nil;
}

static BOOL VCIncySubscriptionURL(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || ![text length] || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kVCMaximumSubscriptionURLBytes) return NO;
    for (NSUInteger i=0;i<[text length];i++) if ([text characterAtIndex:i] <= 0x20 || [text characterAtIndex:i] == 0x7f) return NO;
    NSURL *url=[NSURL URLWithString:text];
    NSString *scheme=[[url scheme] lowercaseString];
    return ([scheme isEqual:@"http"] || [scheme isEqual:@"https"]) && [[url host] length];
}

static NSDictionary *VCIncyDecrypt(NSString *link) {
    static const unsigned char material[64]={
        0xee,0x87,0x6a,0x06,0x3a,0xf7,0x04,0xd7,0xb4,0x09,0xf1,0x91,0x0d,0x97,0x31,0xcc,
        0x14,0x19,0x08,0x1e,0xc0,0x89,0x93,0xa0,0x12,0x70,0x55,0x68,0x73,0xe1,0xef,0x2d,
        0xcf,0x51,0x0d,0xf4,0x3b,0x2a,0xb9,0x7e,0xa9,0x84,0x78,0xee,0xe5,0xf1,0xb1,0xcf,
        0x80,0xe3,0xa4,0x84,0xfc,0x93,0x69,0x31,0x6c,0xcd,0x87,0xe5,0x4b,0x79,0x97,0xb7
    };
    static const char salt[]="incydeepcrypt1v2026.06";
    unsigned char seed[sizeof(salt)-1+sizeof(material)],key[32];
    memcpy(seed,salt,sizeof(salt)-1); memcpy(seed+sizeof(salt)-1,material,sizeof(material));
    unsigned keyLength=0;
    BOOL derived=EVP_Digest(seed,sizeof(seed),key,&keyLength,EVP_sha256(),NULL) == 1 && keyLength == sizeof(key);
    OPENSSL_cleanse(seed,sizeof(seed));
    NSMutableData *wire=VCIncyDecodeBase64([link substringFromIndex:14],YES,kVCMaximumSubscriptionURLBytes);
    NSMutableData *plain=nil;
    NSDictionary *result=nil;
    EVP_CIPHER_CTX *ctx=NULL;
    core_json_t *root=NULL;
    if (!derived || [wire length] < 29) goto done;
    NSUInteger size=[wire length]-28;
    plain=[NSMutableData dataWithLength:size+1];
    const unsigned char *bytes=[wire bytes];
    int written=0,final=0;
    ctx=EVP_CIPHER_CTX_new();
    if (!ctx || EVP_DecryptInit_ex(ctx,EVP_aes_256_gcm(),NULL,key,bytes) != 1 ||
        EVP_DecryptUpdate(ctx,[plain mutableBytes],&written,bytes+12,(int)size) != 1 ||
        EVP_CIPHER_CTX_ctrl(ctx,EVP_CTRL_GCM_SET_TAG,16,(void *)(bytes+12+size)) != 1 ||
        EVP_DecryptFinal_ex(ctx,(unsigned char *)[plain mutableBytes]+written,&final) != 1 || (NSUInteger)(written+final) != size ||
        memchr([plain bytes],0,size)) goto done;
    root=core_json_parse([plain bytes],NULL,0);
    if (!root || root->type != CORE_JSON_OBJECT) goto done;
    for (const core_json_t *field=root->child;field;field=field->next)
        for (const core_json_t *other=field->next;other;other=other->next)
            if (!strcmp(field->key,other->key)) goto done;
    const core_json_t *version=core_json_get(root,"v"),*url=core_json_get(root,"url"),*name=core_json_get(root,"n");
    if (!version || version->type != CORE_JSON_NUMBER || strcmp(version->text,"1") || !url || url->type != CORE_JSON_STRING ||
        (name && name->type != CORE_JSON_STRING)) goto done;
    NSString *target=[NSString stringWithUTF8String:url->text];
    NSString *title=name ? [NSString stringWithUTF8String:name->text] : nil;
    if (!VCIncySubscriptionURL(target) || (name && !title)) goto done;
    if ([title length] > 128) {
        NSUInteger end=128;
        unichar last=[title characterAtIndex:end-1];
        if (last >= 0xd800 && last <= 0xdbff) end--;
        title=[title substringToIndex:end];
    }
    result=@{@"kind":@"subscription",@"value":target,@"source":link,@"name":title ?: @""};
done:
    core_json_free(root);
    EVP_CIPHER_CTX_free(ctx);
    OPENSSL_cleanse(key,sizeof(key));
    VCIncyClearData(plain); VCIncyClearData(wire);
    return result;
}

NSDictionary *VCIncyImportDescriptor(NSString *link, NSString **error) {
    if (error) *error=nil;
    if (!VCIncyIsLink(link)) { if (error) *error=@"Invalid INCY link"; return nil; }
    if ([link lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kVCMaximumSubscriptionBytes) { if (error) *error=@"INCY import exceeds size limit"; return nil; }
    NSRange slash=[link rangeOfString:@"/" options:0 range:NSMakeRange(7,[link length]-7)];
    if (slash.location == NSNotFound) { if (error) *error=@"Unsupported INCY command"; return nil; }
    NSString *command=[[link substringWithRange:NSMakeRange(7,slash.location-7)] lowercaseString];
    if ([command isEqual:@"crypt1"]) {
        NSDictionary *descriptor=[link lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kVCMaximumSubscriptionURLBytes ? VCIncyDecrypt(link) : nil;
        if (!descriptor && error) *error=@"Invalid INCY crypt1 link";
        return descriptor;
    }
    NSString *payload=[link substringFromIndex:slash.location+1];
    if (![payload length] || VCIncyIsLink(payload) || (![command isEqual:@"add"] && ![command isEqual:@"import"])) {
        if (error) *error=@"Invalid or unsupported INCY import"; return nil;
    }
    if ([command isEqual:@"add"] && [payload lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kVCMaximumSubscriptionURLBytes) {
        if (error) *error=@"INCY link exceeds size limit"; return nil;
    }
    return @{@"kind":[command isEqual:@"add"] ? @"link" : @"data",@"value":payload,@"source":link};
}

NSDictionary *VCIncySubscriptionDescriptor(NSString *link, NSString **error) {
    NSDictionary *descriptor=VCIncyImportDescriptor(link,error);
    if (descriptor && !VCIncySubscriptionURL([descriptor objectForKey:@"value"])) {
        if (error) *error=@"INCY link does not contain a subscription URL";
        return nil;
    }
    return descriptor;
}

NSString *VCIncySafeFetchError(NSString *error) {
    if (![error isKindOfClass:[NSString class]]) return @"INCY subscription fetch failed";
    if ([error rangeOfString:@"requires confirmation"].location != NSNotFound) return @"Plain HTTP subscription requires confirmation";
    if ([error rangeOfString:@"cancel" options:NSCaseInsensitiveSearch].location != NSNotFound) return @"INCY subscription operation canceled";
    return @"INCY subscription fetch failed";
}
