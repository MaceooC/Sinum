// Copyright (c) 2025 Project Nova LLC

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

#import <netdb.h>
#import <dlfcn.h>
#import <string.h>

#define API_URL @"https://vanta-api-zyko.duckdns.org"
#define EPIC_GAMES_URL @"ol.epicgames.com"

#define VANTA_XMPP_HOST "vanta-game-zyko.duckdns.org"
#define VANTA_XMPP_PORT "80"


#pragma mark - iOS 27 compatibility fix

static IMP VANTAOriginalSetBrightness = NULL;

static void VANTASetBrightness(
    UIScreen *screen,
    SEL selector,
    CGFloat brightness
)
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
        class_getInstanceMethod(
            [UIScreen class],
            @selector(setBrightness:)
        );

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


#pragma mark - VANTA XMPP redirect

static int (*VANTAOriginalGetAddrInfo)(
    const char *,
    const char *,
    const struct addrinfo *,
    struct addrinfo **
) = NULL;


static int VANTAGetAddrInfo(
    const char *node,
    const char *service,
    const struct addrinfo *hints,
    struct addrinfo **res
)
{
    if (VANTAOriginalGetAddrInfo == NULL) {

        VANTAOriginalGetAddrInfo =
            (void *)dlsym(
                RTLD_NEXT,
                "getaddrinfo"
            );
    }

    if (VANTAOriginalGetAddrInfo == NULL) {
        return EAI_FAIL;
    }

    const char *targetNode = node;
    const char *targetService = service;

    BOOL isEpicXMPP = NO;

    if (node != NULL) {

        if (
            strstr(node, "xmpp") != NULL &&
            strstr(node, "epicgames.com") != NULL
        ) {
            isEpicXMPP = YES;
        }

    }

    if (isEpicXMPP) {

        targetNode = VANTA_XMPP_HOST;

        /*
         Force également le port XMPP VANTA.
         Cela évite que l'ancien client iOS conserve
         le port XMPP Epic d'origine.
        */
        targetService = VANTA_XMPP_PORT;

        NSLog(
            @"[VANTA] XMPP redirect: %s:%s -> %s:%s",
            node ? node : "(null)",
            service ? service : "(null)",
            VANTA_XMPP_HOST,
            VANTA_XMPP_PORT
        );
    }

    return VANTAOriginalGetAddrInfo(
        targetNode,
        targetService,
        hints,
        res
    );
}


#define VANTA_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _vanta_interpose_##_replacee \
__attribute__((section("__DATA,__interpose"))) = { \
    (const void *)&_replacement, \
    (const void *)&_replacee \
};

VANTA_INTERPOSE(
    VANTAGetAddrInfo,
    getaddrinfo
)


#pragma mark - Sinum API redirect

@interface CustomURLProtocol : NSURLProtocol
@end


@implementation CustomURLProtocol


+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *absoluteURLString =
        [[request URL] absoluteString];

    if (
        [absoluteURLString containsString:EPIC_GAMES_URL] &&
        ![absoluteURLString containsString:@"/CloudDir/"]
    )
    {
        if (
            [NSURLProtocol propertyForKey:@"Handled"
                                inRequest:request]
        ) {
            return NO;
        }

        return YES;
    }

    return NO;
}


+ (NSURLRequest *)canonicalRequestForRequest:
    (NSURLRequest *)request
{
    return request;
}


- (void)startLoading
{
    NSMutableURLRequest *modifiedRequest =
        [[self request] mutableCopy];

    NSString *originalPath =
        [modifiedRequest.URL path];

    NSString *newBaseURLString =
        API_URL;

    NSURLComponents *components =
        [NSURLComponents
            componentsWithString:newBaseURLString];

    components.path = originalPath;

    NSURLComponents *originalComponents =
        [NSURLComponents
            componentsWithURL:modifiedRequest.URL
            resolvingAgainstBaseURL:NO];

    if (originalComponents.queryItems.count > 0) {

        NSMutableArray<NSURLQueryItem *> *cleanItems =
            [NSMutableArray array];

        for (
            NSURLQueryItem *item
            in originalComponents.queryItems
        )
        {
            NSString *decodedValue =
                item.value
                    ? [item.value stringByRemovingPercentEncoding]
                    : nil;

            [cleanItems addObject:
                [NSURLQueryItem
                    queryItemWithName:item.name
                    value:decodedValue]
            ];
        }

        components.queryItems =
            cleanItems;
    }

    [modifiedRequest
        setURL:components.URL];

    [NSURLProtocol
        setProperty:@YES
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
    /*
     Fix du crash iOS 27 lié à UIScreen brightness.
    */
    VANTAInstallIOS27CompatibilityFix();

    /*
     Redirection des requêtes Epic HTTP/HTTPS
     vers le backend VANTA.
    */
    [NSURLProtocol
        registerClass:[CustomURLProtocol class]];
}
