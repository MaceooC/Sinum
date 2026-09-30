// Copyright (c) 2025 Project Nova LLC

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

#define API_URL @"https://vanta-api-zyko.duckdns.org"
#define EPIC_GAMES_URL @"ol.epicgames.com"


#pragma mark - iOS 27 compatibility fix

static IMP VANTAOriginalSetBrightness = NULL;

static void VANTASetBrightness(UIScreen *screen, SEL selector, CGFloat brightness)
{
    if (VANTAOriginalSetBrightness == NULL) {
        return;
    }

    if ([NSThread isMainThread]) {
        ((void (*)(id, SEL, CGFloat))VANTAOriginalSetBrightness)(
            screen,
            selector,
            brightness
        );

        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        ((void (*)(id, SEL, CGFloat))VANTAOriginalSetBrightness)(
            screen,
            selector,
            brightness
        );
    });
}

static void VANTAInstallIOS27CompatibilityFix(void)
{
    Method method =
        class_getInstanceMethod([UIScreen class], @selector(setBrightness:));

    if (method == NULL) {
        return;
    }

    VANTAOriginalSetBrightness =
        method_getImplementation(method);

    method_setImplementation(
        method,
        (IMP)VANTASetBrightness
    );
}


#pragma mark - Sinum redirect

@interface CustomURLProtocol : NSURLProtocol
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *absoluteURLString =
        [[request URL] absoluteString];

    if ([absoluteURLString containsString:EPIC_GAMES_URL] &&
        ![absoluteURLString containsString:@"/CloudDir/"])
    {
        if ([NSURLProtocol propertyForKey:@"Handled"
                                inRequest:request])
        {
            return NO;
        }

        return YES;
    }

    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSMutableURLRequest *modifiedRequest =
        [[self request] mutableCopy];

    NSString *originalPath =
        [modifiedRequest.URL path];

    NSURLComponents *components =
        [NSURLComponents componentsWithString:API_URL];

    components.path = originalPath;

    NSURLComponents *originalComponents =
        [NSURLComponents componentsWithURL:modifiedRequest.URL
                    resolvingAgainstBaseURL:NO];

    if (originalComponents.queryItems.count > 0) {

        NSMutableArray<NSURLQueryItem *> *cleanItems =
            [NSMutableArray array];

        for (NSURLQueryItem *item in originalComponents.queryItems) {

            NSString *decodedValue =
                item.value
                    ? [item.value stringByRemovingPercentEncoding]
                    : nil;

            [cleanItems addObject:
                [NSURLQueryItem queryItemWithName:item.name
                                             value:decodedValue]];
        }

        components.queryItems = cleanItems;
    }

    [modifiedRequest setURL:components.URL];

    [NSURLProtocol setProperty:@YES
                        forKey:@"Handled"
                     inRequest:modifiedRequest];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"

    [[self client]
        URLProtocol:self
        wasRedirectedToRequest:modifiedRequest
        redirectResponse:nil];

#pragma clang diagnostic pop
}

- (void)stopLoading
{
}

@end


#pragma mark - Entry

__attribute__((constructor))
static void entry(void)
{
    VANTAInstallIOS27CompatibilityFix();

    [NSURLProtocol registerClass:[CustomURLProtocol class]];
}
