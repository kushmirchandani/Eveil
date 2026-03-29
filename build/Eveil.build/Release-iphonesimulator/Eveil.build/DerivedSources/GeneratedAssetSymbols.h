#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "background-1" asset catalog image resource.
static NSString * const ACImageNameBackground1 AC_SWIFT_PRIVATE = @"background-1";

#undef AC_SWIFT_PRIVATE
