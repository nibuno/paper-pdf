#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

static void drawLine(CGContextRef context, NSString *text, CGFloat x, CGFloat y, CGFloat size) {
    CTFontRef font = CTFontCreateWithName(CFSTR("HiraginoSans-W3"), size, NULL);
    NSDictionary *attributes = @{
        (__bridge NSString *)kCTFontAttributeName: (__bridge id)font,
        (__bridge NSString *)kCTForegroundColorAttributeName: (__bridge id)CGColorGetConstantColor(kCGColorBlack)
    };
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
    CGContextSetTextPosition(context, x, y);
    CTLineDraw(line, context);
    CFRelease(line);
    CFRelease(font);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: generate_test_pdf OUTPUT.pdf\n");
            return 64;
        }

        NSString *path = [NSString stringWithUTF8String:argv[1]];
        NSURL *url = [NSURL fileURLWithPath:path];
        CGRect mediaBox = CGRectMake(0, 0, 595, 842);
        CGContextRef context = CGPDFContextCreateWithURL((__bridge CFURLRef)url, &mediaBox, NULL);
        if (!context) {
            fprintf(stderr, "failed to create PDF\n");
            return 1;
        }

        for (NSInteger pageNumber = 1; pageNumber <= 8; pageNumber++) {
            CGPDFContextBeginPage(context, NULL);
            CGContextSetFillColorWithColor(context, CGColorGetConstantColor(kCGColorWhite));
            CGContextFillRect(context, mediaBox);
            drawLine(context, @"Swift + PDFKit 技術検証", 56, 770, 23);
            drawLine(
                context,
                [NSString stringWithFormat:@"紙の読み跡を確認するページ %ld / 8", (long)pageNumber],
                56,
                720,
                15
            );
            drawLine(context, @"let document = PDFDocument(url: sourceURL)", 56, 665, 14);
            drawLine(context, @"線やメモは自動保存され、元のPDFファイルは変更しません。", 56, 620, 15);
            drawLine(
                context,
                [NSString stringWithFormat:@"第%ld章  PDF座標と画面座標", (long)pageNumber],
                56,
                550,
                18
            );
            drawLine(context, @"ページを読み返すと、紙の小口に少しずつ跡が残ります。", 56, 510, 14);
            CGPDFContextEndPage(context);
        }
        CGPDFContextClose(context);
        CGContextRelease(context);

        printf("generated %s\n", path.UTF8String);
    }
    return 0;
}
