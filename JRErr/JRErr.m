// JRErr.m semver:2.0.0b1
//   Copyright (c) 2012-2013 Jonathan 'Wolf' Rentzsch: http://rentzsch.com
//   Some rights reserved: http://opensource.org/licenses/mit
//   https://github.com/rentzsch/JRErr

#import "JRErr.h"

NSString * const JRErrDomain = @"JRErrDomain";

static void CreateAndReportError(intptr_t exprResultValue, JRErrCallContext *callContext) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       [NSString stringWithUTF8String:callContext->file], @"__FILE__",
                                       [NSNumber numberWithInt:callContext->line], @"__LINE__",
                                       [NSString stringWithUTF8String:callContext->function], @"__PRETTY_FUNCTION__",
                                       [NSString stringWithUTF8String:callContext->expr], @"EXPR",
                                       [NSThread callStackSymbols], @"callStack",
                                       nil];
    if (callContext->annotator) {
        callContext->annotator(callContext->error,
                               callContext->exprResultType,
                               exprResultValue,
                               userInfo);
    }
    NSError *mergedError;
    if (callContext->error) {
        [userInfo setValuesForKeysWithDictionary:[callContext->error userInfo]];
        mergedError = [NSError errorWithDomain:[callContext->error domain]
                                          code:[callContext->error code]
                                      userInfo:userInfo];
    } else {
        mergedError = [NSError errorWithDomain:JRErrDomain
                                          code:-1
                                      userInfo:userInfo];
    }
    [[JRErrContext currentContext] pushError:mergedError];
    if (callContext->shouldThrow) {
        @throw [JRErrException exceptionWithError:mergedError];
    }
}

#define CALL_BLOCK_IMPL(TYPE) \
    TYPE result = block(); \
    if (callContext->detector(callContext->exprResultType, (intptr_t)result)) { \
        CreateAndReportError((intptr_t)result, callContext); \
    } \
    return result;

id     __attribute__((overloadable)) xcall_block(id     (^block)(void), JRErrCallContext *callContext) {
    CALL_BLOCK_IMPL(id);
}

BOOL   __attribute__((overloadable)) xcall_block(BOOL   (^block)(void), JRErrCallContext *callContext) {
    CALL_BLOCK_IMPL(BOOL);
}

void*  __attribute__((overloadable)) xcall_block(void*  (^block)(void), JRErrCallContext *callContext) {
    CALL_BLOCK_IMPL(void*);
}

void   __attribute__((overloadable)) xcall_block(void   (^block)(void), JRErrCallContext *callContext) {
    block();
    if (callContext->detector(callContext->exprResultType, -1)) {
        CreateAndReportError(-1, callContext);
    }
}

//-----------------------------------------------------------------------------------------

BOOL JRErrStandardDetector(const char *codeResultType, intptr_t codeResultValue) {
    if (codeResultType[1] == 0 && codeResultType[0] == 'c') {
        // @encode(BOOL)
        return codeResultValue == NO;
    } else {
        return codeResultValue ? YES : NO;
    }
}

void JRErrStandardAnnotator(NSError *error,
                            const char *exprResultType,
                            intptr_t exprResultValue,
                            NSMutableDictionary *errorUserInfo)
{
	// No-op (here primarily for documentation purposes).
}

void JRErrRunLoopObserver(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    JRErrContext *errContext = [JRErrContext currentContext];
    for (NSError *error in errContext.errorStack) {
        NSLog(@"unhandled error: %@", error);
    }
    [errContext.errorStack removeAllObjects];
}

@implementation JRErrContext
@synthesize errorStack;

- (id)init {
    self = [super init];
    if (self) {
        errorStack = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [errorStack release];
    [super dealloc];
}

+ (JRErrContext*)currentContext {
    NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
    JRErrContext *result = [threadDict objectForKey:@"locoErrorContext"];
    if (!result) {
        result = [[[JRErrContext alloc] init] autorelease];
        [threadDict setObject:result forKey:@"locoErrorContext"];
        
        CFRunLoopObserverContext observerContext = {0, NULL, NULL, NULL, NULL};
        CFRunLoopObserverRef observer = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                                                kCFRunLoopExit,
                                                                true,
                                                                0,
                                                                JRErrRunLoopObserver,
                                                                &observerContext);
        CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer, kCFRunLoopCommonModes);
        
    }
    return result;
}

- (NSError*)currentError {
    return [self.errorStack lastObject];
}

- (void)pushError:(NSError*)error {
    [self.errorStack addObject:error];
}

- (NSError*)popError {
    NSError *result = [self.errorStack lastObject];
    if (result) {
        [self.errorStack removeLastObject];
    }
    return result;
}

@end

@implementation JRErrException

+ (id)exceptionWithError:(NSError*)error {
    return [[[self alloc] initWithError:error] autorelease];
}

- (id)initWithError:(NSError*)error {
    self = [super initWithName:@"NSError"
                        reason:[error description]
                      userInfo:[NSDictionary dictionaryWithObject:error
                                                           forKey:@"error"]];
    return self;
}

@end