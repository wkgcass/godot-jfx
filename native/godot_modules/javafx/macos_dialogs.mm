#include "unix_dialogs.h"

#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <cstdio>

// Cocoa half of the macOS file-dialog service. Panels are created, presented
// and dismissed on the AppKit main thread (which is the Godot main thread);
// the completion handler publishes the result exactly like the Windows
// worker-thread dialog does. beginSheetModal/beginWithCompletionHandler are
// asynchronous, so the Godot main loop keeps pumping frames while a chooser
// is open.
namespace godot_javafx::unix_dialogs {

static NSString *to_nsstring(const std::u16string &p_value) {
	if (p_value.empty()) return nil;
	return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar *>(p_value.data()) length:NSUInteger(p_value.size())];
}

static std::u16string to_u16(NSString *p_value) {
	const NSUInteger length = [p_value length];
	std::u16string result(size_t(length), 0);
	if (length) [p_value getCharacters:reinterpret_cast<unichar *>(result.data()) range:NSMakeRange(0, length)];
	return result;
}

// One ExtensionFilter pattern list ("*.txt;*.jpg") → content types. "*"/"*.*"
// map to UTTypeData with allowsOtherFileTypes, mirroring the Godot editor's
// own open/save delegate. Unknown extensions still resolve to dynamic UTTypes
// that match by filename extension, so nothing valid is filtered out.
static NSArray<UTType *> *content_types_for(const std::u16string &p_patterns, bool &r_all_files) {
	NSMutableArray<UTType *> *types = [NSMutableArray array];
	r_all_files = false;
	size_t start = 0;
	while (start <= p_patterns.size()) {
		size_t end = p_patterns.find(u';', start);
		if (end == std::u16string::npos) end = p_patterns.size();
		std::u16string pattern = p_patterns.substr(start, end - start);
		start = end + 1;
		while (!pattern.empty() && pattern.front() == u' ') pattern.erase(pattern.begin());
		while (!pattern.empty() && pattern.back() == u' ') pattern.pop_back();
		if (pattern.empty()) continue;
		if (pattern == u"*" || pattern == u"*.*") {
			r_all_files = true;
			continue;
		}
		if (pattern.size() > 2 && pattern[0] == u'*' && pattern[1] == u'.') pattern.erase(0, 2);
		if (pattern.empty()) continue;
		UTType *type = [UTType typeWithFilenameExtension:to_nsstring(pattern)];
		if (type) [types addObject:type];
	}
	if (r_all_files) return @[ UTTypeData ];
	return [types count] ? types : nil;
}

} // namespace godot_javafx::unix_dialogs

// Filter popup accessory and selected-index tracking, in the spirit of
// GodotOpenSaveDelegate but without editor-specific options.
@interface GodotJavaFXDialogFilters : NSObject {
@public
	NSArray<NSArray<UTType *> *> *groups;
	NSInteger index;
	NSSavePanel *panel; // The panel it configures; owned by the panel context.
}
- (instancetype)initWithPanel:(NSSavePanel *)p_panel names:(const std::vector<std::u16string> *)names patterns:(const std::vector<std::u16string> *)patterns selected:(NSInteger)selected;
- (void)popupAction:(id)sender;
@end

@implementation GodotJavaFXDialogFilters

- (instancetype)initWithPanel:(NSSavePanel *)p_panel names:(const std::vector<std::u16string> *)names patterns:(const std::vector<std::u16string> *)patterns selected:(NSInteger)selected {
	self = [super init];
	if (!self) return nil;
	index = selected;
	panel = p_panel;
	NSMutableArray<NSArray<UTType *> *> *built = [NSMutableArray arrayWithCapacity:names->size()];
	for (size_t i = 0; i < names->size(); ++i) {
		bool all = false;
		NSArray<UTType *> *types = godot_javafx::unix_dialogs::content_types_for((*patterns)[i], all);
		if (all) {
			// A "match everything" entry keeps the popup item but lifts the
			// restriction, like the Godot editor's UTTypeData fallback.
			NSMutableArray<UTType *> *group = [NSMutableArray arrayWithObject:UTTypeData];
			if (types) [group addObjectsFromArray:types];
			[built addObject:group];
		} else if (types) {
			[built addObject:types];
		} else {
			// An unresolvable extension list must not silently accept unrelated
			// files: an empty group rejects every selection for this entry.
			[built addObject:@[]];
		}
	}
	groups = built;
	NSPopUpButton *popup = nil;
	if (names->size() > 1) {
		NSView *base = [[NSView alloc] initWithFrame:NSZeroRect];
		base.translatesAutoresizingMaskIntoConstraints = NO;
		NSTextField *label = [NSTextField labelWithString:NSLocalizedString(@"Format", @"file dialog filter label")];
		label.textColor = NSColor.secondaryLabelColor;
		label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
		popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
		for (size_t i = 0; i < names->size(); ++i)
			[popup addItemWithTitle:godot_javafx::unix_dialogs::to_nsstring((*names)[i])];
		[popup selectItemAtIndex:selected];
		popup.target = self;
		popup.action = @selector(popupAction:);
		NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:2 rows:1];
		grid.translatesAutoresizingMaskIntoConstraints = NO;
		grid.columnSpacing = 10;
		grid.rowAlignment = NSGridRowAlignmentLastBaseline;
		[grid addRowWithViews:@[ label, popup ]];
		[base addSubview:grid];
		[NSLayoutConstraint activateConstraints:@[
			[grid.topAnchor constraintEqualToAnchor:base.topAnchor constant:10],
			[base.bottomAnchor constraintEqualToAnchor:grid.bottomAnchor constant:10],
			[base.centerXAnchor constraintEqualToAnchor:grid.centerXAnchor constant:-10],
		]];
		[p_panel setAccessoryView:base];
	}
	[self applyTo:p_panel at:index];
	return self;
}

- (void)applyTo:(NSSavePanel *)p_panel at:(NSInteger)p_index {
	if (p_index < 0 || p_index >= NSInteger([groups count])) return;
	index = p_index;
	NSArray<UTType *> *group = [groups objectAtIndex:NSUInteger(p_index)];
	if ([group count] == 1 && [group objectAtIndex:0] == UTTypeData) {
		[p_panel setAllowedContentTypes:@[ UTTypeData ]];
		[p_panel setAllowsOtherFileTypes:YES];
	} else {
		[p_panel setAllowsOtherFileTypes:NO];
		[p_panel setAllowedContentTypes:group];
	}
}

- (void)popupAction:(id)sender {
	NSPopUpButton *popup = sender;
	if (!popup || !panel) return;
	[self applyTo:panel at:[popup indexOfSelectedItem]];
}

@end

namespace godot_javafx::unix_dialogs {

// The service admits one dialog at a time, so one retained panel context is
// enough. The completion handler clears it, so an abort arriving after
// dismissal is a harmless no-op.
struct PanelContext {
	NSSavePanel *panel = nil;
	GodotJavaFXDialogFilters *filters = nil;
	Service *service = nullptr;
	std::shared_ptr<Request> request;
};
static PanelContext g_context;

void *panel_present(const std::shared_ptr<Request> &p_request, Service *p_service, void *p_owner) {
	@autoreleasepool {
		const Request &r = *p_request;
		if (g_context.panel) throw std::runtime_error("A macOS file dialog is already presented");
		NSSavePanel *panel = nil;
		if (r.mode == 2) {
			NSSavePanel *save = [NSSavePanel savePanel];
			[save setCanCreateDirectories:YES];
			[save setExtensionHidden:YES];
			[save setCanSelectHiddenExtension:YES];
			if (!r.filename.empty()) [save setNameFieldStringValue:to_nsstring(r.filename)];
			panel = save;
		} else {
			NSOpenPanel *open = [NSOpenPanel openPanel];
			[open setCanChooseFiles:r.mode != 3];
			[open setCanChooseDirectories:r.mode == 3];
			[open setAllowsMultipleSelection:r.mode == 1];
			[open setCanCreateDirectories:r.mode == 3];
			panel = open;
		}
		if (!r.title.empty()) [panel setTitle:to_nsstring(r.title)];
		if (!r.folder.empty()) {
			NSString *path = to_nsstring(r.folder);
			BOOL is_directory = NO;
			if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&is_directory] || !is_directory)
				throw std::runtime_error("Resolve initial folder failed");
			[panel setDirectoryURL:[NSURL fileURLWithPath:path]];
		}
		GodotJavaFXDialogFilters *filters = nil;
		if (r.mode != 3 && !r.names.empty()) {
			filters = [[GodotJavaFXDialogFilters alloc] initWithPanel:panel names:&r.names patterns:&r.patterns selected:r.selected];
			if (!filters) throw std::runtime_error("Cannot allocate the file-dialog filter accessory");
		}
		g_context.panel = panel;
		g_context.filters = filters;
		g_context.service = p_service;
		g_context.request = p_request;
		std::shared_ptr<Request> request = p_request;
		void (^completion)(NSInteger) = ^(NSInteger result) {
			@autoreleasepool {
				if (result == NSModalResponseOK && !request->cancel.load(std::memory_order_acquire)) {
					NSOpenPanel *open = [panel isKindOfClass:[NSOpenPanel class]] ? (NSOpenPanel *)panel : nil;
					NSArray<NSURL *> *urls = open ? [open URLs] : @[ [panel URL] ];
					if ([urls count] > 4096) {
						request->error = "File selection exceeds 4096 paths";
					} else {
						try {
							for (NSURL *url in urls) {
								NSString *path = [url path];
								if (path) request->files.push_back(to_u16(path));
							}
						} catch (const std::bad_alloc &) {
							request->error = "File-dialog result allocation failed";
						}
						request->selected = filters ? int(filters->index) : -1;
					}
				} else {
					request->selected = -1;
				}
				Service *service = g_context.service;
				void *identity = (__bridge void *)panel;
				g_context.panel = nil;
				g_context.filters = nil;
				g_context.service = nullptr;
				g_context.request.reset();
				request->done.store(true, std::memory_order_release);
				if (service) service->panel_closed(identity);
			}
		};
		NSWindow *owner = (__bridge NSWindow *)p_owner;
		if (owner && ![owner isKindOfClass:[NSPanel class]]) {
			[panel beginSheetModalForWindow:owner completionHandler:completion];
		} else {
			[panel beginWithCompletionHandler:completion];
		}
		return (__bridge void *)panel;
	}
}

void panel_abort(void *p_panel) {
	if (!p_panel || (__bridge void *)g_context.panel != p_panel) return;
	// cancel: dismisses both sheet and standalone presentations; the completion
	// handler publishes the cancellation result.
	[g_context.panel cancel:nil];
}

void panel_detach(Service *p_service) {
	if (g_context.service == p_service) g_context.service = nullptr;
}

} // namespace godot_javafx::unix_dialogs
