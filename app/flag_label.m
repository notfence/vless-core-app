#import "flag_label.h"
#import <CoreText/CoreText.h>
#include "../common/flag_logic.h"

static NSString * const assetAttribute=@"VCFlagAsset";
static NSString * const sourceAttribute=@"VCFlagSource";
static const size_t cacheLimit=256*1024;

@interface VCFlagImage : NSObject {
@public CGImageRef image;
}
@end
@implementation VCFlagImage
- (void)dealloc { if (image) CGImageRelease(image); [super dealloc]; }
@end

@interface VCFlagImageCache : NSObject {
    NSMutableDictionary *_images;
    NSMutableArray *_order;
    size_t _bytes;
}
- (CGImageRef)imageForAsset:(NSString *)asset;
- (void)clear;
@end

@implementation VCFlagImageCache
- (id)init {
    if ((self=[super init])) {
        _images=[[NSMutableDictionary alloc] init]; _order=[[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_images release]; [_order release]; [super dealloc];
}
- (void)clear { [_images removeAllObjects]; [_order removeAllObjects]; _bytes=0; }
- (void)memoryWarning:(NSNotification *)notification { (void)notification; [self clear]; }
- (CGImageRef)imageForAsset:(NSString *)asset {
    VCFlagImage *entry=[_images objectForKey:asset];
    if (entry) { [_order removeObject:asset]; [_order addObject:asset]; return entry->image; }
    NSString *path=[[NSBundle mainBundle] pathForResource:asset ofType:@"png" inDirectory:@"flags"];
    if (!path) return NULL;
    CGDataProviderRef provider=CGDataProviderCreateWithFilename([path fileSystemRepresentation]);
    if (!provider) return NULL;
    CGImageRef source=CGImageCreateWithPNGDataProvider(provider,NULL,YES,kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    if (!source) return NULL;
    size_t width=CGImageGetWidth(source), height=CGImageGetHeight(source);
    if (width!=72 || height!=72) { CGImageRelease(source); return NULL; }
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    if (!space) { CGImageRelease(source); return NULL; }
    CGContextRef context=CGBitmapContextCreate(NULL,width,height,8,width*4,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) { CGImageRelease(source); return NULL; }
    CGContextClearRect(context,CGRectMake(0,0,width,height));
    CGContextDrawImage(context,CGRectMake(0,0,width,height),source);
    CGImageRelease(source);
    CGImageRef decoded=CGBitmapContextCreateImage(context); CGContextRelease(context);
    if (!decoded) return NULL;
    size_t cost=CGImageGetBytesPerRow(decoded)*CGImageGetHeight(decoded);
    while (_bytes+cost>cacheLimit && [_order count]) {
        NSString *old=[_order objectAtIndex:0]; VCFlagImage *item=[_images objectForKey:old];
        _bytes-=CGImageGetBytesPerRow(item->image)*CGImageGetHeight(item->image);
        [_images removeObjectForKey:old]; [_order removeObjectAtIndex:0];
    }
    entry=[[VCFlagImage alloc] init]; entry->image=decoded;
    [_images setObject:entry forKey:asset]; [_order addObject:asset]; _bytes+=cost; [entry release];
    return decoded;
}
@end

static VCFlagImageCache *imageCache(void) {
    static VCFlagImageCache *cache;
    if (!cache) cache=[[VCFlagImageCache alloc] init];
    return cache;
}

typedef struct { CGFloat ascent,descent,width; } VCFlagRunMetrics;
static void freeMetrics(void *value) { free(value); }
static CGFloat runAscent(void *value) { return ((VCFlagRunMetrics *)value)->ascent; }
static CGFloat runDescent(void *value) { return ((VCFlagRunMetrics *)value)->descent; }
static CGFloat runWidth(void *value) { return ((VCFlagRunMetrics *)value)->width; }

@interface VCFlagTextLayout : NSObject {
@public NSString *text; UIFont *font; UIColor *color; BOOL hasFlags;
    NSAttributedString *_string;
    CTTypesetterRef _typesetter;
}
- (id)initWithText:(NSString *)value font:(UIFont *)type color:(UIColor *)ink;
- (NSArray *)linesForWidth:(CGFloat)width count:(NSInteger)count mode:(NSLineBreakMode)mode;
- (CGSize)sizeForWidth:(CGFloat)width count:(NSInteger)count mode:(NSLineBreakMode)mode;
- (BOOL)drawInRect:(CGRect)rect count:(NSInteger)count mode:(NSLineBreakMode)mode alignment:(NSTextAlignment)alignment;
@end

@implementation VCFlagTextLayout
- (id)initWithText:(NSString *)value font:(UIFont *)type color:(UIColor *)ink {
    if (!(self=[super init])) return nil;
    text=[value copy]; font=[type retain]; color=[ink retain];
    NSUInteger length=[text length];
    const unichar *characters=CFStringGetCharactersPtr((CFStringRef)text);
    NSMutableData *storage=nil;
    if (!characters) {
        storage=[NSMutableData dataWithLength:length*sizeof(unichar)];
        if (length) [text getCharacters:[storage mutableBytes] range:NSMakeRange(0,length)];
        characters=[storage bytes];
    }
    size_t cursor=0, previous=0; VCFlagMatch match;
    NSMutableAttributedString *prepared=nil;
    while (VCFlagNext(characters,length,&cursor,&match)) {
        NSString *asset=[NSString stringWithUTF8String:match.asset];
        if (![imageCache() imageForAsset:asset]) continue;
        VCFlagRunMetrics *metrics=malloc(sizeof(*metrics));
        if (!metrics) continue;
        metrics->ascent=font.ascender; metrics->descent=MAX(0,font.lineHeight-font.ascender); metrics->width=font.lineHeight;
        CTRunDelegateCallbacks callbacks={kCTRunDelegateCurrentVersion,freeMetrics,runAscent,runDescent,runWidth};
        CTRunDelegateRef delegate=CTRunDelegateCreate(&callbacks,metrics);
        if (!delegate) { free(metrics); continue; }
        if (!prepared) prepared=[[[NSMutableAttributedString alloc] init] autorelease];
        if (match.location>previous) [prepared appendAttributedString:[[[NSAttributedString alloc] initWithString:[text substringWithRange:NSMakeRange(previous,match.location-previous)]] autorelease]];
        NSString *original=[text substringWithRange:NSMakeRange(match.location,match.length)];
        NSDictionary *attributes=[NSDictionary dictionaryWithObjectsAndKeys:(id)delegate,(id)kCTRunDelegateAttributeName,asset,assetAttribute,original,sourceAttribute,nil];
        [prepared appendAttributedString:[[[NSAttributedString alloc] initWithString:@"\ufffc" attributes:attributes] autorelease]];
        CFRelease(delegate); previous=match.location+match.length; hasFlags=YES;
    }
    if (!hasFlags) return self;
    if (previous<length) [prepared appendAttributedString:[[[NSAttributedString alloc] initWithString:[text substringFromIndex:previous]] autorelease]];
    CTFontRef ctfont=CTFontCreateWithName((CFStringRef)font.fontName,font.pointSize,NULL);
    if (!ctfont) { hasFlags=NO; return self; }
    [prepared addAttribute:(id)kCTFontAttributeName value:(id)ctfont range:NSMakeRange(0,[prepared length])]; CFRelease(ctfont);
    [prepared addAttribute:(id)kCTForegroundColorAttributeName value:(id)color.CGColor range:NSMakeRange(0,[prepared length])];
    _string=[prepared copy]; _typesetter=CTTypesetterCreateWithAttributedString((CFAttributedStringRef)_string);
    if (!_typesetter) hasFlags=NO;
    return self;
}
- (void)dealloc {
    if (_typesetter) CFRelease(_typesetter);
    [_string release]; [text release]; [font release]; [color release]; [super dealloc];
}
- (NSArray *)linesForWidth:(CGFloat)width count:(NSInteger)count mode:(NSLineBreakMode)mode {
    if (!hasFlags || width<=0) return [NSArray array];
    NSMutableArray *lines=[NSMutableArray array]; CFIndex offset=0, length=[_string length];
    while (offset<length && (!count || [lines count]<(NSUInteger)count)) {
        BOOL last=count>0 && [lines count]+1==(NSUInteger)count;
        BOOL truncates=mode==NSLineBreakByTruncatingHead || mode==NSLineBreakByTruncatingMiddle || mode==NSLineBreakByTruncatingTail;
        CFIndex n=mode==NSLineBreakByCharWrapping ? CTTypesetterSuggestClusterBreak(_typesetter,offset,width) : CTTypesetterSuggestLineBreak(_typesetter,offset,width);
        BOOL hiddenParagraph=NO;
        if (last && (truncates || mode==NSLineBreakByClipping)) {
            NSRange paragraph=[[_string string] rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet] options:0 range:NSMakeRange(offset,length-offset)];
            n=paragraph.location==NSNotFound ? length-offset : MAX(1,(CFIndex)paragraph.location-offset);
            hiddenParagraph=offset+n<length;
        }
        if (n<=0) break;
        CTLineRef line=CTTypesetterCreateLine(_typesetter,CFRangeMake(offset,n));
        if (!line) return nil;
        if (last && truncates && (hiddenParagraph || CTLineGetTypographicBounds(line,NULL,NULL,NULL)>width)) {
            NSAttributedString *dots=[[[NSAttributedString alloc] initWithString:@"\u2026" attributes:[_string attributesAtIndex:0 effectiveRange:NULL]] autorelease];
            NSMutableAttributedString *tokenString=[[[NSMutableAttributedString alloc] initWithAttributedString:dots] autorelease];
            [tokenString removeAttribute:(id)kCTRunDelegateAttributeName range:NSMakeRange(0,1)];
            [tokenString removeAttribute:assetAttribute range:NSMakeRange(0,1)];
            [tokenString removeAttribute:sourceAttribute range:NSMakeRange(0,1)];
            CTLineRef token=CTLineCreateWithAttributedString((CFAttributedStringRef)tokenString);
            if (!token) { CFRelease(line); return nil; }
            if (hiddenParagraph) {
                NSMutableAttributedString *paragraph=[[[NSMutableAttributedString alloc] initWithAttributedString:[_string attributedSubstringFromRange:NSMakeRange(offset,n)]] autorelease];
                [paragraph appendAttributedString:tokenString];
                CFRelease(line); line=CTLineCreateWithAttributedString((CFAttributedStringRef)paragraph);
                if (!line) { CFRelease(token); return nil; }
            }
            CTLineTruncationType kind=mode==NSLineBreakByTruncatingHead ? kCTLineTruncationStart : mode==NSLineBreakByTruncatingMiddle ? kCTLineTruncationMiddle : kCTLineTruncationEnd;
            CTLineRef truncated=CTLineCreateTruncatedLine(line,width,kind,token);
            if (token) CFRelease(token);
            CFRelease(line); line=truncated;
        }
        if (!line) return nil;
        [lines addObject:(id)line]; CFRelease(line); offset+=n;
    }
    return lines;
}
- (CGSize)sizeForWidth:(CGFloat)width count:(NSInteger)count mode:(NSLineBreakMode)mode {
    NSArray *lines=[self linesForWidth:width count:count mode:mode]; CGFloat widest=0;
    if (!lines) return [text sizeWithFont:font constrainedToSize:CGSizeMake(width,CGFLOAT_MAX) lineBreakMode:mode];
    for (id item in lines) widest=MAX(widest,CTLineGetTypographicBounds((CTLineRef)item,NULL,NULL,NULL));
    return CGSizeMake(ceilf(MIN(width,widest)),ceilf([lines count]*font.lineHeight));
}
- (BOOL)drawInRect:(CGRect)rect count:(NSInteger)count mode:(NSLineBreakMode)mode alignment:(NSTextAlignment)alignment {
    NSArray *lines=[self linesForWidth:rect.size.width count:count mode:mode];
    if (!lines) return NO;
    CGContextRef context=UIGraphicsGetCurrentContext(); CGContextSaveGState(context);
    CGContextClipToRect(context,rect); CGContextSetTextMatrix(context,CGAffineTransformIdentity);
    CGContextTranslateCTM(context,rect.origin.x,CGRectGetMaxY(rect)); CGContextScaleCTM(context,1,-1);
    CGFloat top=MAX(0,floorf((rect.size.height-[lines count]*font.lineHeight)*0.5f)); NSUInteger index=0;
    for (id item in lines) {
        CTLineRef line=(CTLineRef)item; CGFloat width=CTLineGetTypographicBounds(line,NULL,NULL,NULL);
        CGFloat x=alignment==NSTextAlignmentCenter ? (rect.size.width-width)*0.5f : alignment==NSTextAlignmentRight ? rect.size.width-width : 0;
        CGFloat y=rect.size.height-top-index++*font.lineHeight-font.ascender;
        for (id value in (NSArray *)CTLineGetGlyphRuns(line)) {
            CTRunRef run=(CTRunRef)value;
            NSDictionary *attributes=(NSDictionary *)CTRunGetAttributes(run);
            NSString *asset=[attributes objectForKey:assetAttribute];
            if (!asset) { CGContextSetTextPosition(context,x,y); CTRunDraw(run,context,CFRangeMake(0,0)); continue; }
            CFIndex glyphs=CTRunGetGlyphCount(run);
            for (CFIndex glyph=0;glyph<MAX((CFIndex)1,glyphs);glyph++) {
                CGPoint position=CGPointZero;
                if (glyphs) CTRunGetPositions(run,CFRangeMake(glyph,1),&position);
                else {
                    position.x=CTLineGetOffsetForStringIndex(line,CTRunGetStringRange(run).location,NULL);
                    if (CTRunGetStatus(run)&kCTRunStatusRightToLeft) position.x-=font.lineHeight;
                }
                CGRect imageRect=CGRectMake(x+position.x,y+position.y-(font.lineHeight-font.ascender),font.lineHeight,font.lineHeight);
                if (CGRectGetMinX(imageRect)<0 || CGRectGetMaxX(imageRect)>rect.size.width) continue;
                CGImageRef image=[imageCache() imageForAsset:asset];
                if (image) { CGContextDrawImage(context,imageRect,image); continue; }
                NSMutableDictionary *fallbackAttributes=[NSMutableDictionary dictionaryWithDictionary:attributes];
                [fallbackAttributes removeObjectForKey:(id)kCTRunDelegateAttributeName];
                [fallbackAttributes removeObjectForKey:assetAttribute]; [fallbackAttributes removeObjectForKey:sourceAttribute];
                NSAttributedString *fallback=[[[NSAttributedString alloc] initWithString:[attributes objectForKey:sourceAttribute] attributes:fallbackAttributes] autorelease];
                CTLineRef original=CTLineCreateWithAttributedString((CFAttributedStringRef)fallback);
                if (original) {
                    CGFloat originalWidth=CTLineGetTypographicBounds(original,NULL,NULL,NULL);
                    CGContextSaveGState(context); CGContextTranslateCTM(context,x+position.x,y+position.y);
                    if (originalWidth>font.lineHeight) CGContextScaleCTM(context,font.lineHeight/originalWidth,1);
                    CGContextSetTextPosition(context,0,0); CTLineDraw(original,context);
                    CGContextRestoreGState(context); CFRelease(original);
                }
            }
        }
    }
    CGContextRestoreGState(context); return YES;
}
@end

@implementation VCFlagLabel
- (void)dealloc { [_flagLayout release]; [super dealloc]; }
- (VCFlagTextLayout *)layoutForWidth:(CGFloat)width {
    UIFont *font=self.font; UIColor *color=self.highlighted && self.highlightedTextColor ? self.highlightedTextColor : self.textColor;
    VCFlagTextLayout *layout=_flagLayout;
    if (!layout || ![layout->text isEqualToString:self.text ?: @""] || ![layout->font isEqual:font] || ![layout->color isEqual:color]) {
        [_flagLayout release]; _flagLayout=[[VCFlagTextLayout alloc] initWithText:self.text ?: @"" font:font color:color]; layout=_flagLayout;
    }
    if (layout->hasFlags && self.adjustsFontSizeToFitWidth && self.numberOfLines==1 && width>0) {
        CGFloat full=[layout sizeForWidth:CGFLOAT_MAX count:1 mode:NSLineBreakByClipping].width;
        if (full>width) {
            CGFloat minimum=[self respondsToSelector:@selector(minimumScaleFactor)] ? self.minimumScaleFactor*font.pointSize : self.minimumFontSize;
            CGFloat size=MAX(minimum,font.pointSize*width/full);
            UIFont *smaller=[UIFont fontWithName:font.fontName size:size];
            return [[[VCFlagTextLayout alloc] initWithText:self.text ?: @"" font:smaller color:color] autorelease];
        }
    }
    return layout;
}
- (void)setText:(NSString *)text {
    if (![self.text isEqualToString:text]) { [_flagLayout release]; _flagLayout=nil; }
    [super setText:text];
}
- (CGSize)sizeThatFits:(CGSize)size {
    VCFlagTextLayout *layout=[self layoutForWidth:size.width];
    return layout->hasFlags ? [layout sizeForWidth:size.width count:self.numberOfLines mode:self.lineBreakMode] : [super sizeThatFits:size];
}
- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)count {
    VCFlagTextLayout *layout=[self layoutForWidth:bounds.size.width];
    if (!layout->hasFlags) return [super textRectForBounds:bounds limitedToNumberOfLines:count];
    CGSize size=[layout sizeForWidth:bounds.size.width count:count mode:self.lineBreakMode];
    return CGRectMake(bounds.origin.x,bounds.origin.y+floorf((bounds.size.height-size.height)*0.5f),bounds.size.width,size.height);
}
- (void)drawTextInRect:(CGRect)rect {
    VCFlagTextLayout *layout=[self layoutForWidth:rect.size.width];
    if (!layout->hasFlags) { [super drawTextInRect:rect]; return; }
    CGContextRef context=UIGraphicsGetCurrentContext(); CGContextSaveGState(context);
    if (self.shadowColor) CGContextSetShadowWithColor(context,self.shadowOffset,0,self.shadowColor.CGColor);
    BOOL drawn=[layout drawInRect:rect count:self.numberOfLines mode:self.lineBreakMode alignment:self.textAlignment];
    CGContextRestoreGState(context);
    if (!drawn) [super drawTextInRect:rect];
}
@end

CGSize VCFlagTextSize(NSString *text, UIFont *font, CGSize constraint, NSLineBreakMode mode) {
    VCFlagTextLayout *layout=[[[VCFlagTextLayout alloc] initWithText:text ?: @"" font:font color:[UIColor blackColor]] autorelease];
    if (!layout->hasFlags) return [text sizeWithFont:font constrainedToSize:constraint lineBreakMode:mode];
    CGSize size=[layout sizeForWidth:constraint.width count:0 mode:mode];
    size.height=MIN(size.height,MAX(0,constraint.height)); return size;
}

@implementation VCFlagTableCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if (!(self=[super initWithStyle:style reuseIdentifier:identifier])) return nil;
    UILabel *sources[]={[super textLabel],[super detailTextLabel]};
    UILabel **targets[]={&_flagTitleLabel,&_flagDetailLabel};
    for (NSUInteger i=0;i<2;i++) {
        UILabel *source=sources[i]; if (!source) continue;
        UILabel *label=[[VCFlagLabel alloc] initWithFrame:source.frame];
        label.font=source.font; label.textColor=source.textColor; label.highlightedTextColor=source.highlightedTextColor;
        label.numberOfLines=source.numberOfLines; label.lineBreakMode=source.lineBreakMode;
        label.backgroundColor=[UIColor clearColor]; *targets[i]=label;
        source.hidden=YES; [self.contentView addSubview:label];
    }
    return self;
}
- (void)dealloc { [_flagTitleLabel release]; [_flagDetailLabel release]; [super dealloc]; }
- (UILabel *)textLabel { return _flagTitleLabel ?: [super textLabel]; }
- (UILabel *)detailTextLabel { return _flagDetailLabel ?: [super detailTextLabel]; }
- (void)prepareForReuse {
    [super prepareForReuse]; _flagTitleLabel.text=nil; _flagDetailLabel.text=nil;
}
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    _flagTitleLabel.highlighted=highlighted; _flagDetailLabel.highlighted=highlighted;
}
- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    _flagTitleLabel.highlighted=selected; _flagDetailLabel.highlighted=selected;
}
- (void)layoutSubviews {
    UILabel *sources[]={[super textLabel],[super detailTextLabel]};
    UILabel *targets[]={_flagTitleLabel,_flagDetailLabel};
    for (NSUInteger i=0;i<2;i++) {
        sources[i].text=targets[i].text; sources[i].font=targets[i].font;
        sources[i].numberOfLines=targets[i].numberOfLines;
        sources[i].lineBreakMode=targets[i].lineBreakMode;
    }
    [super layoutSubviews];
    for (NSUInteger i=0;i<2;i++) { targets[i].frame=sources[i].frame; sources[i].hidden=YES; }
}
@end
