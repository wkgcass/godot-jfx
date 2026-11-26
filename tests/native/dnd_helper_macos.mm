// macOS counterpart of dnd_helper.cpp: a chromeless topmost Cocoa endpoint
// for the cross-process drag/drop fixture. Two modes:
//   dnd_helper_macos target <x> <y> <w> <h> <logfile>
//   dnd_helper_macos source <x> <y> <w> <h> <logfile> <text> <url> <file> <custom>
// Coordinates are JavaFX logical points with a top-left origin (the Godot
// wrapper places native helpers in the same space; CoreGraphics/NSWindow
// conversion happens here). Log lines mirror the Windows helper so the test
// scripts can share their assertions: DND_HELPER_READY / _ENTER / _LEAVE /
// _DROP / _SOURCE_DONE.
#import <AppKit/AppKit.h>

// NSPasteboardItem (macOS 26) rejects type strings that are not valid UTIs,
// so files publish as file URLs and the custom payload uses the UTI twin of
// the module's application/x-godot-custom-* MIME convention (its '/' becomes
// '.'). The system synthesizes the classic filename list on the dragging
// pasteboard, which keeps path strings verbatim for the target read.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSString *const CUSTOM_TYPE = @"application.x-godot-custom-token";

static FILE *g_log = nil;

static void log_line(NSString *line) {
	if (!g_log) return;
	fprintf(g_log, "%s\n", [line UTF8String]);
	fflush(g_log);
}

static NSString *pasteboard_text(NSPasteboard *pasteboard, NSPasteboardType type) {
	NSString *value = [pasteboard stringForType:type];
	return value ? value : @"";
}

// Drop endpoint: accepts copy of text/url/files/custom payloads and logs them.
@interface HelperDropView : NSView
@end

@implementation HelperDropView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	NSPoint point = [sender draggingLocation];
	// AppKit reports the item frame in points. The Robot samples the composited
	// preview on this panel while the pointer is held over it.
	__block NSSize size = NSZeroSize;
	[sender enumerateDraggingItemsWithOptions:0 forView:self
			classes:@[ [NSPasteboardItem class] ] searchOptions:@{}
			usingBlock:^(NSDraggingItem *item, NSInteger idx, BOOL *stop) {
		size = item.draggingFrame.size;
		*stop = YES;
	}];
	log_line([NSString stringWithFormat:@"DND_HELPER_ENTER x=%ld y=%ld effect=1 image=%dx%d",
			(long)point.x, (long)point.y, (int)size.width, (int)size.height]);
	return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
	log_line(@"DND_HELPER_LEAVE");
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender { return YES; }

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	NSPasteboard *pasteboard = [sender draggingPasteboard];
	NSString *text = pasteboard_text(pasteboard, NSPasteboardTypeString);
	NSString *url = pasteboard_text(pasteboard, NSPasteboardTypeURL);
	// Collect file paths: the pasteboard-level filename plist (synthesized by
	// the system from file-url items) round-trips strings verbatim, file URLs
	// are converted back to paths.
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	id legacy = [pasteboard propertyListForType:NSFilenamesPboardType];
	if ([legacy isKindOfClass:[NSArray class]]) {
		for (id entry in (NSArray *)legacy)
			if ([entry isKindOfClass:[NSString class]]) [paths addObject:(NSString *)entry];
	}
	NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[ [NSURL class] ]
			options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
	for (NSURL *file_url in urls) {
		NSString *path = [file_url path];
		if (path && ![paths containsObject:path]) [paths addObject:path];
	}
	NSData *custom_data = [pasteboard dataForType:CUSTOM_TYPE];
	NSString *custom = custom_data ? [[NSString alloc] initWithData:custom_data encoding:NSUTF8StringEncoding] : @"";
	if (!custom) custom = @"";
	NSString *first = [paths count] ? paths[0] : @"";
	log_line([NSString stringWithFormat:@"DND_HELPER_DROP text=[%@] url=[%@] files=%lu first=[%@] custom=[%@]",
			text, url, (unsigned long)[paths count], first, custom]);
	return YES;
}
@end

// Drag source endpoint: starts a Cocoa drag session on mouse drag, carrying
// the payload given on the command line.
@interface HelperSourceView : NSView <NSDraggingSource> {
	@public
	NSString *text, *url, *file, *custom;
	BOOL started;
}
@end

@implementation HelperSourceView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)mouseDragged:(NSEvent *)event {
	if (started) return;
	started = YES;
	NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
	[item setString:text forType:NSPasteboardTypeString];
	[item setString:url forType:NSPasteboardTypeURL];
	[item setData:[custom dataUsingEncoding:NSUTF8StringEncoding] forType:CUSTOM_TYPE];
	NSMutableArray<NSDraggingItem *> *items = [NSMutableArray array];
	NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFileType:@"public.data"];
	[icon setSize:NSMakeSize(32, 32)];
	NSRect frame = NSMakeRect([event locationInWindow].x - 16, [event locationInWindow].y - 16, 32, 32);
	NSDraggingItem *main_drag = [[NSDraggingItem alloc] initWithPasteboardWriter:item];
	[main_drag setDraggingFrame:frame contents:icon];
	[items addObject:main_drag];
	// Files ride as per-item NSURL writers (NSPasteboardItem rejects the
	// classic filename plist type). The file must exist on disk: cross-process
	// serialization silently drops file items whose path is missing.
	NSURL *file_url = [NSURL fileURLWithPath:file];
	NSDraggingItem *file_drag = [[NSDraggingItem alloc] initWithPasteboardWriter:file_url];
	[file_drag setDraggingFrame:frame contents:icon];
	[items addObject:file_drag];
	[self beginDraggingSessionWithItems:items event:event source:self];
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	return NSDragOperationCopy;
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	log_line([NSString stringWithFormat:@"DND_HELPER_SOURCE_DONE effect=%d", (operation & NSDragOperationCopy) ? 1 : 0]);
}
@end

static NSWindow *make_window(CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSView *view) {
	// JavaFX coordinates are top-left origin points; Cocoa frames are
	// bottom-left origin on the primary screen.
	CGFloat screen_height = [[NSScreen screens][0] frame].size.height;
	NSRect frame = NSMakeRect(x, screen_height - y - h, w, h);
	NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
			styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
			backing:NSBackingStoreBuffered defer:NO];
	[panel setLevel:NSStatusWindowLevel];
	[panel setBackgroundColor:[NSColor colorWithCalibratedRed:0 green:90.0 / 255.0 blue:160.0 / 255.0 alpha:1]];
	[panel setOpaque:YES];
	[panel setContentView:view];
	return panel;
}

int main(int argc, char **argv) {
	@autoreleasepool {
		if (argc < 7) {
			fprintf(stderr, "usage: dnd_helper_macos target <x> <y> <w> <h> <log> | source <x> <y> <w> <h> <log> <text> <url> <file> <custom>\n");
			return 2;
		}
		BOOL is_target = strcmp(argv[1], "target") == 0;
		BOOL is_source = strcmp(argv[1], "source") == 0;
		if ((!is_target && !is_source) || (is_source && argc < 11)) {
			fprintf(stderr, "unknown mode: %s\n", argv[1]);
			return 2;
		}
		g_log = fopen(argv[6], "w");
		if (!g_log) {
			fprintf(stderr, "cannot open log: %s\n", argv[6]);
			return 1;
		}
		CGFloat x = atof(argv[2]), y = atof(argv[3]), w = atof(argv[4]), h = atof(argv[5]);

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

		NSView *view;
		if (is_target) {
			view = [[HelperDropView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
			[view registerForDraggedTypes:@[ NSPasteboardTypeString, NSPasteboardTypeURL,
					NSPasteboardTypeFileURL, @"public.html",
					NSPasteboardTypeRTF, CUSTOM_TYPE ]];
		} else {
			HelperSourceView *source = [[HelperSourceView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
			source->text = [NSString stringWithUTF8String:argv[7]];
			source->url = [NSString stringWithUTF8String:argv[8]];
			source->file = [NSString stringWithUTF8String:argv[9]];
			source->custom = [NSString stringWithUTF8String:argv[10]];
			view = source;
		}
		NSWindow *window = make_window(x, y, w, h, view);
		[window orderFrontRegardless];
		log_line(@"DND_HELPER_READY");
		[NSApp run];
	}
	return 0;
}
