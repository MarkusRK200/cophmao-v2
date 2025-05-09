//
//  LEANDocumentSharer.m
//  GoNativeIOS
//
//  Created by Weiyin He on 8/26/14.
//  Copyright (c) 2014 GoNative.io LLC. All rights reserved.
//

#import "LEANDocumentSharer.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "GonativeIO-Swift.h"
#import "LEANUtilities.h"
#import "LEANPDFManager.h"

@interface LEANDocumentSharer ()
@property UIDocumentInteractionController *interactionController;
@property NSArray *allowableMimeTypes;
@property NSString *imageMimePrefix;
@property NSURLRequest *lastRequest;
@property NSURLResponse *lastResponse;
@property NSURL *dataFile;
@property NSFileHandle *dataFileHandle;
@property NSMutableArray *sharableRequests; // array of nsurlrequests
@property BOOL isFinished;
@property BOOL isSharableFile;
@property (nonatomic, copy) void (^downloadImageCompletion)(NSDictionary *result);
@end

@implementation LEANDocumentSharer
+ (LEANDocumentSharer *)sharedSharer
{
    static LEANDocumentSharer *sharedSharer;
    
    @synchronized(self)
    {
        if (!sharedSharer){
            sharedSharer = [[LEANDocumentSharer alloc] init];
        }
        return sharedSharer;
    }
}

- (instancetype) init
{
    self = [super init];
    if (self) {
        self.allowableMimeTypes = @[@"application/pdf", // pdf
                                    
                                    @"application/octet-stream",
                                    
                                    // word
                                    @"application/msword",
                                    @"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                                    @"application/vnd.ms-word.document.macroEnabled.12",
                                    @"application/vnd.ms-excel",
                                    
                                    // excel
                                    @"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                    @"application/vnd.ms-excel.sheet.macroEnabled.12",
                                    @"application/vnd.ms-excel.sheet.binary.macroEnabled.12",
                                    @"application/vnd.ms-powerpoint",
                                    
                                    // powerpoint
                                    @"application/vnd.openxmlformats-officedocument.presentationml.presentation",
                                    @"application/vnd.openxmlformats-officedocument.presentationml.slideshow",
                                    @"application/vnd.ms-powerpoint.presentation.macroEnabled.12",
                                    @"application/vnd.ms-powerpoint.slideshow.macroEnabled.12",
                                    
                                    // Apple pages
                                    @"application/vnd.iwork.pages.archive",
                                    @"application/vnd.iwork.pages",
                                    @"application/x-iwork-pages-sffkey",
                                    
                                    // Apple numbers
                                    @"application/vnd.iwork.numbers.archive",
                                    @"application/vnd.iwork.numbers",
                                    @"application/x-iwork-numbers-sffkey",
                                    
                                    // Apple keynote
                                    @"application/vnd.iwork.keynote.archive",
                                    @"application/vnd.iwork.keynote",
                                    @"application/x-iwork-keynote-sffkey",
                                    
                                    @"application/zip"]; // many MS office documents may be auto-detect as zip files
        self.imageMimePrefix = @"image/";
        self.sharableRequests = [NSMutableArray array];
    }
    return self;
}


- (void)receivedRequest:(NSURLRequest*)request
{
    self.lastRequest = request;
    self.isSharableFile = NO;
    self.isFinished = NO;
    
    self.dataFile = nil;
    [self.dataFileHandle closeFile];
    self.dataFileHandle = nil;
}


- (void)receivedResponse:(NSURLResponse*)response
{
    self.lastResponse = response;
    self.isFinished = NO;
    
    // check mime types
    if ([self.allowableMimeTypes containsObject:response.MIMEType] || [response.MIMEType hasPrefix:self.imageMimePrefix]) {
        self.isSharableFile = YES;
        [self.sharableRequests addObject:self.lastRequest];
    }
}

- (void)receivedWebviewResponse:(NSURLResponse *)response
{
    self.lastResponse = response;
    self.isFinished = YES;
    self.dataFile = nil;
    
    // check mime types
    if ([self.allowableMimeTypes containsObject:response.MIMEType] || [response.MIMEType hasPrefix:self.imageMimePrefix]) {
        self.isSharableFile = YES;
        [self.sharableRequests addObject:self.lastRequest];
    }
}


- (void)receivedData:(NSData *)data
{
    self.isFinished = NO;
    
    if (!self.isSharableFile) {
        return;
    }
    
    if (!self.dataFile) {
        NSURL *cacheDir = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]];
        self.dataFile = [cacheDir URLByAppendingPathComponent:@"io.gonative.documentsharer.cachedfile"];
    }
    
    if (!self.dataFileHandle) {
        [[NSFileManager defaultManager] createFileAtPath:[self.dataFile path] contents:nil attributes:nil];
        NSError *error;
        self.dataFileHandle = [NSFileHandle fileHandleForWritingToURL:self.dataFile error:&error];
        if (error) {
            NSLog(@"Error creating file for document sharer: %@", error);
            self.dataFileHandle = nil;
            return;
        }
    }
    
    [self.dataFileHandle writeData:data];
}

- (void)cancel
{
    [self.dataFileHandle closeFile];
    self.dataFileHandle = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.dataFile error:nil];
    self.isFinished = NO;
}

- (void)finish
{
    [self.dataFileHandle closeFile];
    self.dataFileHandle = nil;
    self.isFinished = YES;
}

- (BOOL)isSharableRequest:(NSURLRequest *)req
{
    if (self.lastRequest && self.lastResponse && self.isFinished
        && [LEANDocumentSharer request:self.lastRequest matchesRequest:req]){
        return self.isSharableFile;
    } else {
        for (NSURLRequest *savedRequest in self.sharableRequests) {
            if ([LEANDocumentSharer request:req matchesRequest:savedRequest]) {
                return YES;
            }
        }
    }
    
    return NO;
}

+ (BOOL)request:(NSURLRequest*)req1 matchesRequest:(NSURLRequest*)req2
{
    return [req1.URL.absoluteString isEqualToString:req2.URL.absoluteString]
    && [req1.HTTPMethod isEqualToString:req1.HTTPMethod]
    && req1.HTTPBody == req2.HTTPBody
    && req1.HTTPBodyStream == req2.HTTPBodyStream;
}

- (void)shareUrl:(NSURL*)url fromView:(UIView*)view {
    [self shareUrl:url fromView:view filename:nil];
}

- (void)shareUrl:(NSURL*)url fromView:(UIView*)view filename:(NSString*)filename {
    [self shareUrl:url fromView:view filename:filename open:NO completion:nil];
}

- (void)shareUrl:(NSURL*)url fromView:(UIView*)view filename:(NSString*)filename open:(BOOL)open completion:(void (^)(NSString *error))completion {
    if (!url) return;
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    
    // Add user-agent
    NSString *userAgent = [[GoNativeAppConfig sharedAppConfig] userAgentForUrl:url];
    if (userAgent) {
        [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    
    // If using WKWebView on iOS11+, get cookies from WKHTTPCookieStore
    BOOL gettingWKWebviewCookies = NO;
    if ([GoNativeAppConfig sharedAppConfig].useWKWebView) {
        if (@available(iOS 11.0, *)) {
            gettingWKWebviewCookies = YES;
            WKHTTPCookieStore *cookieStore = [WKWebsiteDataStore defaultDataStore].httpCookieStore;
            [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> * _Nonnull cookies) {
                NSMutableArray *cookiesToSend = [NSMutableArray array];
                for (NSHTTPCookie *cookie in cookies) {
                    if ([LEANUtilities cookie:cookie matchesUrl:url]) {
                        [cookiesToSend addObject:cookie];
                    }
                }
                NSDictionary *headerFields = [NSHTTPCookie requestHeaderFieldsWithCookies:cookiesToSend];
                NSString *cookieHeader = headerFields[@"Cookie"];
                if (cookieHeader) {
                    [req addValue:cookieHeader forHTTPHeaderField:@"Cookie"];
                }
                [self shareRequest:req from:view force:YES filename:filename open:open completion:completion];
            }];
        }
    }
    if (!gettingWKWebviewCookies) {
        [self shareRequest:req from:view force:YES filename:filename open:open completion:completion];
    }
}

- (void)shareRequest:(NSURLRequest *)req fromButton:(UIBarButtonItem*)button {
    [self shareRequest:req from:button force:NO filename:nil open:NO completion:nil];
}

- (void)shareRequest:(NSURLRequest *)req from:(id)buttonOrView force:(BOOL)force filename:(NSString *)filename open:(BOOL)open completion:(void (^)(NSString *error))completion {
    if (!force && ![self isSharableRequest:req]) {
        return;
    }
    
    UIBarButtonItem *button = nil;
    UIView *view = nil;
    if (buttonOrView) {
        if ([buttonOrView isKindOfClass:[UIBarButtonItem class]]) {
            button = buttonOrView;
        } else if ([buttonOrView isKindOfClass:[UIView class]]) {
            view = buttonOrView;
        }
    }
    
    // is the last request we intercepted
    if ([LEANDocumentSharer request:req matchesRequest:self.lastRequest] && self.dataFile) {
        // copy to documents folder with a good suggested file name
        NSURL *documentsDir = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
        NSURL *sharedFile = [documentsDir URLByAppendingPathComponent:filename ?: [self getFilenameFromUrlResponse:self.lastResponse]];
        [[NSFileManager defaultManager] removeItemAtURL:sharedFile error:nil];
        [[NSFileManager defaultManager] copyItemAtURL:self.dataFile toURL:sharedFile error:nil];
        
        if (!sharedFile) {
            return [self runCompletion:completion error:@"Invalid local file url."];
        }
        
        if (open && [[LEANPDFManager shared] shouldHandleResponse:self.lastResponse]) {
            [[LEANPDFManager shared] openPDF:sharedFile wvc:[self topMostViewController]];
            return [self runCompletion:completion error:nil];
        }
        
        // launch the interaction controller
        self.interactionController = [UIDocumentInteractionController interactionControllerWithURL:sharedFile];
        [self.interactionController presentOpenInMenuFromBarButtonItem:button animated:YES];
        return [self runCompletion:completion error:nil];
    } else {
        // download the file
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithRequest:req completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
            if (error || httpResponse.statusCode != 200 || !location) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    button.enabled = YES;
                });
                
                if (error.localizedDescription) {
                    return [self runCompletion:completion error:error.localizedDescription];
                } else if (httpResponse.statusCode != 200) {
                    return [self runCompletion:completion error:[NSString stringWithFormat:@"Received status code %ld", httpResponse.statusCode]];
                } else if (!location) {
                    return [self runCompletion:completion error:@"Invalid file location."];
                } else {
                    return [self runCompletion:completion error:@"Unknown error."];
                }
            }
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSURL *documentsDirectoryPath = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
            NSURL *destination = [documentsDirectoryPath URLByAppendingPathComponent:filename ?: [self getFilenameFromUrlResponse:response]];
            [fileManager removeItemAtURL:destination error:nil];
            [fileManager moveItemAtURL:location toURL:destination error:nil];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (open && [[LEANPDFManager shared] shouldHandleResponse:response]) {
                    button.enabled = YES;
                    [[LEANPDFManager shared] openPDF:destination wvc:[self topMostViewController]];
                    return [self runCompletion:completion error:nil];
                }
                
                self.interactionController = [UIDocumentInteractionController interactionControllerWithURL:destination];
                self.interactionController.UTI = [LEANUtilities utiFromMimetype:response.MIMEType];
                if (button) {
                    [self.interactionController presentOpenInMenuFromBarButtonItem:button animated:YES];
                } else if (view) {
                    [self.interactionController presentOpenInMenuFromRect:CGRectZero inView:view animated:YES];
                } else {
                    [self.interactionController presentOpenInMenuFromRect:CGRectZero inView:[UIApplication sharedApplication].currentKeyWindow animated:YES];
                }
                button.enabled = YES;
                return [self runCompletion:completion error:nil];
            });
        }];
        
        button.enabled = NO;
        [downloadTask resume];
    }
}

- (void)runCompletion:(void (^)(NSString *error))completion error:(NSString *)error {
    if (completion) {
        completion(error);
    }
}

- (NSString *)getFilenameFromUrlResponse:(id)response {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
        NSString *contentDisposition = headers[@"Content-Disposition"];
        
        if (contentDisposition) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"filename=\"(.*)\"" options:0 error:nil];
            NSTextCheckingResult *result = [regex firstMatchInString:contentDisposition options:0 range:NSMakeRange(0, contentDisposition.length)];
            if (result && result.numberOfRanges > 1) {
                NSRange filenameRange = [result rangeAtIndex:1];
                NSString *filename = [contentDisposition substringWithRange:filenameRange];
                return filename;
            }
        }
    }
    
    if ([response isKindOfClass:[NSURLResponse class]]) {
        return [response suggestedFilename];
    }
    
    return nil;
}

- (UIViewController *)topMostViewController {
    UIViewController *vc = [UIApplication sharedApplication].currentKeyWindow.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

- (void)downloadImage:(NSURL*)url completion:(void (^)(NSDictionary *result))completion {
    if (!url) return;
    self.downloadImageCompletion = completion;
    NSData *data = [NSData dataWithContentsOfURL:url];
    UIImage *image = [[UIImage alloc] initWithData:data];
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (self.downloadImageCompletion) {
        if (error) {
            self.downloadImageCompletion(@{ @"success": @NO, @"error": error.localizedDescription });
        } else {
            self.downloadImageCompletion(@{ @"success": @YES });
        }
        self.downloadImageCompletion = nil;
    }
}

- (void)shareDataUrl:(NSURL *)url {
    if (![url.scheme isEqualToString:@"data"]) {
        return;
    }

    NSData *data = [NSData dataWithContentsOfURL:url];
    NSString *dataString = [url.absoluteString stringByReplacingOccurrencesOfString:@"data:" withString:@""];
    NSString *mimeType = [dataString componentsSeparatedByString:@";"].firstObject;
    NSString *extension = [mimeType componentsSeparatedByString:@"/"].lastObject;
    NSString *filename = [NSString stringWithFormat:@"download.%@", extension];
    NSURL *tempDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL *destination = [tempDirectory URLByAppendingPathComponent:filename];
    
    [[NSFileManager defaultManager] removeItemAtURL:destination error:nil];
    if (![data writeToURL:destination options:NSDataWritingAtomic error:nil]) {
        return;
    }
    
    self.interactionController = [UIDocumentInteractionController interactionControllerWithURL:destination];
    self.interactionController.UTI = [LEANUtilities utiFromMimetype:mimeType];
    [self.interactionController presentOptionsMenuFromRect:CGRectZero inView:[self topMostViewController].view animated:YES];
}

@end
