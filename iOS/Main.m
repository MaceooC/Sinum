// VANTA iOS adapter. Retains Sinum's original request redirection behavior.
// Based on Project Nova Sinum iOS/Main.m (copyright 2025 Project Nova LLC).
// The backend URL is now read from the app's Info.plist at runtime.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *const kEpicGamesDomain = @"ol.epicgames.com";
static NSString *const kBackendSetting = @"VANTABackendURL";

static NSURLComponents *VantaBaseURL(void) {
    id configured = [[NSBundle mainBundle] objectForInfoDictionaryKey:kBackendSetting];
    if (![configured isKindOfClass:[NSString class]]) return nil;
    NSString *url = (NSString *)configured;
    NSURLComponents *components = [NSURLComponents componentsWithString:url];
    if (!components || !components.host || components.host.length == 0) return nil;
    if (![components.scheme isEqualToString:@"http"] && ![components.scheme isEqualToString:@"https"]) return nil;
    if (components.query || components.fragment || (components.path.length && ![components.path isEqualToString:@"/"])) return nil;
    return components;
}

@interface CustomURLProtocol : NSURLProtocol
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *absoluteURLString = [[request URL] absoluteString];
    if (!VantaBaseURL()) return NO;
    if ([absoluteURLString containsString:kEpicGamesDomain] &&
        ![absoluteURLString containsString:@"/CloudDir/"]) {
        if ([NSURLProtocol propertyForKey:@"Handled" inRequest:request]) return NO;
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *modifiedRequest = [[self request] mutableCopy];
    NSString *originalPath = [modifiedRequest.URL path];
    NSURLComponents *components = VantaBaseURL();
    if (!components) {
        NSError *error = [NSError errorWithDomain:@"VANTABackendURL" code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid VANTABackendURL in Info.plist"}];
        [[self client] URLProtocol:self didFailWithError:error];
        return;
    }
    components.path = originalPath;

    NSURLComponents *originalComponents = [NSURLComponents componentsWithURL:modifiedRequest.URL
                                                resolvingAgainstBaseURL:NO];
    if (originalComponents.queryItems.count > 0) {
        NSMutableArray<NSURLQueryItem *> *cleanItems = [NSMutableArray array];
        for (NSURLQueryItem *item in originalComponents.queryItems) {
            NSString *decodedValue = item.value ? [item.value stringByRemovingPercentEncoding] : nil;
            [cleanItems addObject:[NSURLQueryItem queryItemWithName:item.name value:decodedValue]];
        }
        components.queryItems = cleanItems;
    }

    [modifiedRequest setURL:components.URL];
    [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:modifiedRequest];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    [[self client] URLProtocol:self wasRedirectedToRequest:modifiedRequest redirectResponse:nil];
#pragma clang diagnostic pop
}

- (void)stopLoading {}
@end

__attribute__((constructor)) static void VantaEntry(void) {
    [NSURLProtocol registerClass:[CustomURLProtocol class]];
}
