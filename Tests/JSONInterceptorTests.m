#import "JSONInterceptor.h"
#include <stdio.h>
#include <stdlib.h>
static void Check(BOOL condition, const char *name) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", name); exit(1); }
    printf("PASS: %s\n", name);
}
static NSData *Bytes(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
static id Decode(NSData *d) { return [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingFragmentsAllowed error:NULL]; }
int main(void) {
    @autoreleasepool {
        Check([Decode(TOOverrideJSON(Bytes(@"{\"credits\":0}")))[@"credits"] isEqual:@999], "1 credits");
        Check([Decode(TOOverrideJSON(Bytes(@"{\"subscriptionType\":null}")))[@"subscriptionType"] isEqual:@"ULTIMATE"], "2 subscription");
        for (NSString *input in @[@"{\"subscriptionExpiration\":\"null\"}", @"{\"subscriptionExpiration\":null}"])
            Check([Decode(TOOverrideJSON(Bytes(input)))[@"subscriptionExpiration"] isEqual:@"2027-10-14T23:59:59Z"], "3 expiration string/null");
        NSDictionary *output = Decode(TOOverrideJSON(Bytes(@"{\"credits\":0,\"other\":{\"n\":12,\"ok\":true,\"s\":\"é\"}}")));
        Check([output[@"other"] isEqual:Decode(Bytes(@"{\"n\":12,\"ok\":true,\"s\":\"é\"}"))], "4 unrelated values");
        NSData *untouched = Bytes(@" { \"other\": [1,null,true] } ");
        Check(TOOverrideJSON(untouched) == untouched, "5 byte-identical passthrough");
        output = Decode(TOOverrideJSON(Bytes(@"{\"a\":[{\"credits\":0,\"subscriptionType\":null,\"subscriptionExpiration\":null}]}")));
        NSDictionary *nested = output[@"a"][0];
        Check([nested[@"credits"] isEqual:@999] && [nested[@"subscriptionType"] isEqual:@"ULTIMATE"] && [nested[@"subscriptionExpiration"] isEqual:@"2027-10-14T23:59:59Z"], "6 nested array/object");
        NSData *invalid = Bytes(@"{bad");
        Check(TOOverrideJSON(invalid) == invalid, "7 invalid JSON");
        NSData *existing = Bytes(@"{\"credits\":15,\"subscriptionType\":\"PRO\",\"subscriptionExpiration\":\"2028\"}");
        Check(TOOverrideJSON(existing) == existing, "8 preserve non-matching values");
        NSData *boolean = Bytes(@"{\"credits\":false}");
        Check(TOOverrideJSON(boolean) == boolean, "9 do not coerce boolean");
        Check(TOOverrideJSON(nil) == nil, "10 nil");
        NSData *scalar = Bytes(@"42");
        Check(TOOverrideJSON(scalar) == scalar, "11 scalar passthrough");
        NSMutableString *deep = [NSMutableString string];
        for (NSUInteger i = 0; i < 140; i++) [deep appendString:@"["];
        [deep appendString:@"{\"credits\":0}"];
        for (NSUInteger i = 0; i < 140; i++) [deep appendString:@"]"];
        NSData *deepData = Bytes(deep);
        Check(TOOverrideJSON(deepData) == deepData, "12 depth guard");
        NSMutableData *large = [NSMutableData dataWithLength:8 * 1024 * 1024 + 1];
        Check(TOOverrideJSON(large) == large, "13 size guard");
    }
    return 0;
}
