#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>

static NSString *yesNo(BOOL value) {
    return value ? @"yes" : @"no";
}

static BOOL containsJapanese(NSString *text) {
    NSCharacterSet *japanese = [NSCharacterSet characterSetWithRange:NSMakeRange(0x3040, 0x30FF - 0x3040 + 1)];
    return [text rangeOfCharacterFromSet:japanese].location != NSNotFound;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "usage: pdfkit_smoke INPUT.pdf SIDECAR.json\n");
            return 64;
        }

        NSURL *pdfURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSURL *sidecarURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        NSData *originalBytes = [NSData dataWithContentsOfURL:pdfURL];
        PDFDocument *document = [[PDFDocument alloc] initWithURL:pdfURL];
        if (!document || document.pageCount == 0) {
            fprintf(stderr, "PDFKit could not open the document\n");
            return 1;
        }

        PDFPage *page = [document pageAtIndex:0];
        NSString *text = page.string ?: @"";
        BOOL extractedText = text.length > 0;
        BOOL foundJapanese = containsJapanese(text);

        NSUInteger annotationCountBefore = page.annotations.count;
        BOOL annotationAdded = NO;
        if (document.allowsCommenting) {
            PDFAnnotation *annotation = [[PDFAnnotation alloc]
                initWithBounds:NSMakeRect(54, 605, 420, 26)
                forType:PDFAnnotationSubtypeInk
                withProperties:nil];
            PDFBorder *border = [[PDFBorder alloc] init];
            border.lineWidth = 1.6;
            annotation.border = border;
            annotation.color = [NSColor colorWithCalibratedWhite:0.18 alpha:0.75];
            NSBezierPath *path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(3, 5)];
            [path lineToPoint:NSMakePoint(405, 6)];
            [annotation addBezierPath:path];
            [page addAnnotation:annotation];
            annotationAdded = page.annotations.count == annotationCountBefore + 1;
        }

        NSDictionary *sidecar = @{
            @"version": @1,
            @"sourceFilename": pdfURL.lastPathComponent,
            @"pageNotes": @{ @"0": @"原本とは別に保存した検証メモ" },
            @"strokes": @[
                @{
                    @"pageIndex": @0,
                    @"points": @[
                        @{ @"x": @57, @"y": @610 },
                        @{ @"x": @459, @"y": @611 }
                    ]
                }
            ]
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:sidecar options:NSJSONWritingPrettyPrinted error:nil];
        BOOL sidecarWritten = [json writeToURL:sidecarURL atomically:YES];
        NSData *bytesAfterSidecarWrite = [NSData dataWithContentsOfURL:pdfURL];
        BOOL sourceUnchanged = [originalBytes isEqualToData:bytesAfterSidecarWrite];

        PDFView *view = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 800, 700)];
        view.document = document;
        view.autoScales = YES;
        BOOL viewAcceptedDocument = view.document == document;

        printf("pages=%ld\n", (long)document.pageCount);
        printf("encrypted=%s\n", yesNo(document.isEncrypted).UTF8String);
        printf("locked=%s\n", yesNo(document.isLocked).UTF8String);
        printf("allows_copying=%s\n", yesNo(document.allowsCopying).UTF8String);
        printf("allows_commenting=%s\n", yesNo(document.allowsCommenting).UTF8String);
        printf("allows_document_changes=%s\n", yesNo(document.allowsDocumentChanges).UTF8String);
        printf("text_characters=%ld\n", (long)text.length);
        printf("contains_japanese_text=%s\n", yesNo(foundJapanese).UTF8String);
        printf("in_memory_ink_annotation=%s\n", document.allowsCommenting ? yesNo(annotationAdded).UTF8String : "skipped_permission_denied");
        printf("pdfview_loaded=%s\n", yesNo(viewAcceptedDocument).UTF8String);
        printf("sidecar_written=%s\n", yesNo(sidecarWritten).UTF8String);
        printf("source_pdf_unchanged=%s\n", yesNo(sourceUnchanged).UTF8String);

        BOOL annotationCheckPassed = !document.allowsCommenting || annotationAdded;
        BOOL success = extractedText && annotationCheckPassed && viewAcceptedDocument && sidecarWritten && sourceUnchanged;
        return success ? 0 : 1;
    }
}
