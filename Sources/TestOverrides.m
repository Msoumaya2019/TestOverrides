#import "JSONInterceptor.h"
#import <objc/runtime.h>
#import <os/log.h>
#import <stdlib.h>
#import <string.h>

#ifndef TO_TARGET_BUNDLE_ID
#error TO_TARGET_BUNDLE_ID must be set by build.sh
#endif

BOOL TOEnabled(void) {
    if (![[NSBundle.mainBundle bundleIdentifier] isEqualToString:@TO_TARGET_BUNDLE_ID]) return NO;
    const char *disabled = getenv("TEST_OVERRIDES_DISABLED");
    if (disabled && strcmp(disabled, "1") == 0) return NO;
    return ![NSUserDefaults.standardUserDefaults boolForKey:@"TestOverridesDisabled"];
}

typedef void (^TOCompletion)(NSData *, NSURLResponse *, NSError *);
typedef NSURLSessionDataTask *(*TODataTaskIMP)(id, SEL, id, TOCompletion);

static void Install(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        os_log_error(OS_LOG_DEFAULT, "TestOverrides: missing data task method");
        return;
    }
    TODataTaskIMP original = (TODataTaskIMP)method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^NSURLSessionDataTask *(id session, id input, TOCompletion completion) {
        if (!completion) return original(session, selector, input, completion);
        TOCompletion wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *result = data;
            if (!error && TOEnabled() && [response isKindOfClass:NSHTTPURLResponse.class])
                result = TOOverrideJSON(data);
            completion(result, response, error);
        };
        return original(session, selector, input, wrapped);
    });
    // Add an override if inherited, without modifying a superclass globally.
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    os_log_info(OS_LOG_DEFAULT, "TestOverrides: installed %{public}s on %{public}s", sel_getName(selector), class_getName(cls));
}

__attribute__((constructor)) static void LoadTestOverrides(void) {
    @autoreleasepool {
        os_log_info(OS_LOG_DEFAULT, "TestOverrides: library loaded");
        if (!TOEnabled()) {
            os_log_info(OS_LOG_DEFAULT, "TestOverrides: disabled or bundle mismatch");
            return;
        }
        // Resolve Foundation's actual session implementation at runtime.
        @try {
            Class cls = object_getClass(NSURLSession.sharedSession);
            Install(cls, @selector(dataTaskWithRequest:completionHandler:));
            Install(cls, @selector(dataTaskWithURL:completionHandler:));
        } @catch (__unused NSException *exception) {
            os_log_error(OS_LOG_DEFAULT, "TestOverrides: hook installation aborted");
        }
    }
}
