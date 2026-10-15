#import "JSONInterceptor.h"
#import <os/log.h>

static id Rewrite(id value, NSUInteger depth, NSUInteger *changes) {
    if (depth > 128) @throw [NSException exceptionWithName:@"TO depth" reason:nil userInfo:nil];
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [value mutableCopy];
        for (NSString *key in value) {
            id old = value[key], replacement = nil;
            if ([key isEqual:@"credits"] && [old isKindOfClass:NSNumber.class] &&
                CFGetTypeID((__bridge CFTypeRef)old) != CFBooleanGetTypeID() && [old isEqual:@0]) replacement = @999;
            else if ([key isEqual:@"subscriptionType"] && old == NSNull.null) replacement = @"ULTIMATE";
            else if ([key isEqual:@"subscriptionExpiration"] &&
                     (old == NSNull.null || [old isEqual:@"null"])) replacement = @"2027-10-14T23:59:59Z";
            if (replacement) {
                result[key] = replacement;
                (*changes)++;
                os_log_info(OS_LOG_DEFAULT, "TestOverrides: field %{public}@ replaced", key);
            } else result[key] = Rewrite(old, depth + 1, changes);
        }
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[value count]];
        for (id child in value) [result addObject:Rewrite(child, depth + 1, changes)];
        return result;
    }
    return value;
}

NSData *TOOverrideJSON(NSData *data) {
    // Bound work and allocation. Large payloads pass through unchanged.
    if (!data.length || data.length > 8 * 1024 * 1024) return data;
    @try {
        NSError *error = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:&error];
        if (!json) {
            os_log_debug(OS_LOG_DEFAULT, "TestOverrides: non-JSON/invalid payload passed through");
            return data;
        }
        os_log_debug(OS_LOG_DEFAULT, "TestOverrides: JSON detected");
        NSUInteger changes = 0;
        id rewritten = Rewrite(json, 0, &changes);
        if (!changes) return data;
        NSData *output = [NSJSONSerialization dataWithJSONObject:rewritten options:NSJSONWritingFragmentsAllowed error:&error];
        if (!output) {
            os_log_error(OS_LOG_DEFAULT, "TestOverrides: serialization failed; original retained");
            return data;
        }
        os_log_info(OS_LOG_DEFAULT, "TestOverrides: applied %lu changes", (unsigned long)changes);
        return output;
    } @catch (__unused NSException *exception) {
        os_log_error(OS_LOG_DEFAULT, "TestOverrides: transformation aborted; original retained");
        return data;
    }
}
