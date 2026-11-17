// macOS window title sampler for test-startup.sh.
// Prints one line per on-screen window owned by the given pid: the window
// title, or "(unknown)" when the name is not available (screen recording
// permission missing). Exit code is 0 unless the arguments are invalid.
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>

int main(int argc, char **argv) {
	if (argc != 2) {
		fprintf(stderr, "usage: macos-window-titles <pid>\n");
		return 2;
	}
	@autoreleasepool {
		pid_t pid = (pid_t)atoi(argv[1]);
		CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
		if (!list) {
			return 0;
		}
		for (NSDictionary *entry in (__bridge NSArray *)list) {
			NSNumber *owner = entry[(id)kCGWindowOwnerPID];
			if (!owner || owner.intValue != pid) {
				continue;
			}
			NSString *name = entry[(id)kCGWindowName];
			printf("%s\n", name.length ? name.UTF8String : "(unknown)");
		}
		CFRelease(list);
	}
	return 0;
}
