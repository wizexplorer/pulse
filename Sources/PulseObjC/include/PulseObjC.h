#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns NO instead of crashing if it raises an Objective-C exception.
BOOL PulseTryObjC(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
