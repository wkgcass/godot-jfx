#import <AppKit/AppKit.h>

#include "macos_dnd.h"

#include "platform/macos/display_server_macos.h"

// Cocoa halves of the macOS drag/drop backend; see macos_dnd.h for the shared
// contract. Everything here runs on the AppKit main thread, which is the Godot
// main thread. Objective-C classes must live at global scope, outside the C++
// namespace.

// NSDraggingSource for an outbound JavaFX drag. Lives in g_live_sources from
// begin_source until the session ends; the completion callback fires exactly
// once from draggingSession:endedAtPoint:operation:.
@interface GodotJavaFXDragSource : NSObject <NSDraggingSource> {
	@public
	uint32_t allowed_effects;
	void (*done_callback)(void *, uint32_t);
	void *done_context;
}
@end

static NSMutableSet<GodotJavaFXDragSource *> *g_live_sources = nil;

// Queued outbound drag waiting for the next real mouseDragged dispatch (the
// only place AppKit tracks the physical button for a new dragging session).
@interface GodotJavaFXPendingDrag : NSObject {
	@public
	NSMutableArray<NSDraggingItem *> *items;
	GodotJavaFXDragSource *source;
}
@end

@implementation GodotJavaFXPendingDrag
@end

// Runs from GodotContentView::mouseDragged (one-shot). Starts the session
// with the live event and always consumes: on failure the completion still
// fires with effect 0 so the Java side never waits forever. A nil event is
// the content view's cancellation (mouseUp before any drag event).
static bool javafx_drag_start_handler(void *p_userdata, NSEvent *p_event, NSView *p_view) {
	@autoreleasepool {
		GodotJavaFXPendingDrag *pending = (__bridge_transfer GodotJavaFXPendingDrag *)p_userdata;
		GodotJavaFXDragSource *source = pending->source;
		NSDraggingSession *session = nil;
		if (p_event) {
			session = [p_view beginDraggingSessionWithItems:pending->items event:p_event source:source];
		}
		if (!session) {
			[g_live_sources removeObject:source];
			void (*done)(void *, uint32_t) = source->done_callback;
			void *ctx = source->done_context;
			source->done_callback = nullptr;
			source->done_context = nullptr;
			if (done) done(ctx, 0);
		}
		return true;
	}
}

@implementation GodotJavaFXDragSource
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	using namespace godot_javafx::macos_dnd;
	if (context == NSDraggingContextOutsideApplication) {
		NSDragOperation operation = NSDragOperationNone;
		if (allowed_effects & DROPEFFECT_COPY) operation |= NSDragOperationCopy;
		if (allowed_effects & DROPEFFECT_MOVE) operation |= NSDragOperationMove;
		if (allowed_effects & DROPEFFECT_LINK) operation |= NSDragOperationLink;
		return operation;
	}
	// Within the application the destination delegate decides; offer everything.
	return NSDragOperationEvery;
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	using namespace godot_javafx::macos_dnd;
	uint32_t effect = DROPEFFECT_NONE;
	if (operation & (NSDragOperationCopy | NSDragOperationGeneric)) effect |= DROPEFFECT_COPY;
	if (operation & NSDragOperationMove) effect |= DROPEFFECT_MOVE;
	if (operation & NSDragOperationLink) effect |= DROPEFFECT_LINK;
	void (*done)(void *, uint32_t) = done_callback;
	void *ctx = done_context;
	done_callback = nullptr;
	done_context = nullptr;
	[g_live_sources removeObject:self];
	if (done) done(ctx, effect);
}
@end

// Synthetic dragging info for the in-process drop test hook. Only the
// pasteboard accessor is consumed by extract().
@interface GodotJavaFXDragProbe : NSObject
@property(strong) NSPasteboard *pasteboard;
- (NSPasteboard *)draggingPasteboard;
@end

@implementation GodotJavaFXDragProbe
- (NSPasteboard *)draggingPasteboard {
	return _pasteboard;
}
@end

namespace godot_javafx::macos_dnd {

static NSString *to_nsstring(const std::u16string &value) {
	return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar *>(value.data()) length:value.size()];
}

static bool from_nsstring(NSString *value, std::u16string &out, size_t max_chars) {
	if (!value) return false;
	const NSUInteger length = [value length];
	if (length < 1 || length > max_chars) return false;
	out.resize(length);
	[value getCharacters:reinterpret_cast<unichar *>(out.data()) range:NSMakeRange(0, length)];
	return true;
}

bool extract(void *p_sender, Payload &payload, bool with_data) {
	@autoreleasepool {
		@try {
			id<NSDraggingInfo> info = (__bridge id<NSDraggingInfo>)p_sender;
			NSPasteboard *pasteboard = [info draggingPasteboard];
			if (!pasteboard) return false;
			Payload fresh{};
			NSArray<NSPasteboardType> *types = [pasteboard types];
			fresh.has_text = [types containsObject:NSPasteboardTypeString];
			fresh.has_html = [types containsObject:@"public.html"];
			fresh.has_rtf = [types containsObject:NSPasteboardTypeRTF];
			fresh.has_url = [types containsObject:NSPasteboardTypeURL];
			fresh.has_files = [types containsObject:NSFilenamesPboardType] || [types containsObject:NSPasteboardTypeFileURL];
			for (NSString *type in types) {
				if (fresh.custom.size() >= custom_format::MAX_FORMATS) break;
				const NSUInteger length = [type length];
				if (length < 1 || length > custom_format::MAX_NAME_CHARS) continue;
				std::u16string raw(length, 0);
				[type getCharacters:reinterpret_cast<unichar *>(raw.data()) range:NSMakeRange(0, length)];
				// Drag items publish the UTI twin of the MIME name; foreign
				// types (and the raw MIME, which NSPasteboardItem rejects) skip.
				std::u16string name;
				if (!custom_format::name_from_uti_type(raw, name)) continue;
				std::string bytes;
				if (with_data) {
					NSData *data = [pasteboard dataForType:type];
					const NSUInteger size = data ? [data length] : 0;
					if (size < 1 || size > custom_format::MAX_DATA_BYTES) continue;
					bytes.assign(static_cast<const char *>([data bytes]), size);
					bytes.push_back(0); // The Java contract is NUL-terminated.
				}
				fresh.custom.emplace_back(std::move(name), std::move(bytes));
			}
			if (with_data) {
				if (fresh.has_text && !from_nsstring([pasteboard stringForType:NSPasteboardTypeString], fresh.text, MAX_TEXT_BYTES / 2))
					fresh.has_text = false;
				if (fresh.has_html) {
					NSData *data = [pasteboard dataForType:@"public.html"];
					const NSUInteger size = data ? [data length] : 0;
					if (size < 1 || size > MAX_TEXT_BYTES) fresh.has_html = false;
					else {
						fresh.html.assign(static_cast<const char *>([data bytes]), size);
						fresh.html.push_back(0);
					}
				}
				if (fresh.has_rtf) {
					NSData *data = [pasteboard dataForType:NSPasteboardTypeRTF];
					const NSUInteger size = data ? [data length] : 0;
					if (size < 1 || size > MAX_TEXT_BYTES) fresh.has_rtf = false;
					else {
						fresh.rtf.assign(static_cast<const char *>([data bytes]), size);
						fresh.rtf.push_back(0);
					}
				}
				if (fresh.has_url && !from_nsstring([pasteboard stringForType:NSPasteboardTypeURL], fresh.url, MAX_URL_CHARS))
					fresh.has_url = false;
				if (fresh.has_files) {
					// Classic filename list first: it round-trips path strings
					// verbatim, where NSURL would normalize them.
					std::u16string joined;
					size_t paths = 0;
					auto add_path = [&](NSString *path) {
						if (!path || paths >= MAX_PATHS) return;
						std::u16string value;
						if (!from_nsstring(path, value, MAX_PATH_CHARS)) return;
						if (!joined.empty()) joined += u'\n';
						joined += value;
						++paths;
					};
					id legacy = [pasteboard propertyListForType:NSFilenamesPboardType];
					if ([legacy isKindOfClass:[NSArray class]]) {
						for (id entry in (NSArray *)legacy)
							if ([entry isKindOfClass:[NSString class]]) add_path((NSString *)entry);
					} else {
						for (NSPasteboardItem *item in [pasteboard pasteboardItems]) {
							NSString *url = [item stringForType:NSPasteboardTypeFileURL];
							if (!url) continue;
							add_path([[NSURL URLWithString:url] path]);
						}
					}
					if (paths) fresh.files = std::move(joined);
					else fresh.has_files = false;
				}
			}
			if (!fresh.has_text && !fresh.has_html && !fresh.has_rtf && !fresh.has_url && !fresh.has_files && fresh.custom.empty()) return false;
			if (fresh.has_text) fresh.mimes += "text/plain\n";
			if (fresh.has_html) fresh.mimes += "text/html\n";
			if (fresh.has_rtf) fresh.mimes += "text/rtf\n";
			if (fresh.has_url) fresh.mimes += "text/uri-list\n";
			if (fresh.has_files) fresh.mimes += "application/x-java-file-list\n";
			for (const auto &entry : fresh.custom) {
				// Custom names are validated ASCII, so narrowing cannot lose content.
				for (char16_t letter : entry.first) fresh.mimes.push_back(static_cast<char>(letter));
				fresh.mimes += '\n';
			}
			if (!fresh.mimes.empty()) fresh.mimes.pop_back();
			payload = std::move(fresh);
			return true;
		} @catch (NSException *exception) {
			fprintf(stderr, "JavaFX drag extraction failed: %s\n", [[exception reason] UTF8String]);
			return false;
		}
	}
}

static uint32_t current_key_state() {
	const NSEventModifierFlags flags = [NSEvent modifierFlags];
	uint32_t state = 0;
	if (flags & NSEventModifierFlagShift) state |= KEY_SHIFT;
	if (flags & NSEventModifierFlagControl) state |= KEY_CONTROL;
	return state;
}

static bool handle_impl(TargetHandler &handler, int kind, void *sender, int x, int y, uint32_t *effect) {
	if (!handler.upcall) return false;
	switch (kind) {
		case 1: { // Entered.
			if (!effect || !sender) return false;
			const uint32_t allowed = *effect;
			*effect = DROPEFFECT_NONE;
			// Unsupported payloads fall through to Godot's own file handling.
			if (!extract(sender, handler.enter_payload, true)) return false;
			const jint action = handler.dispatch(1, x, y, allowed, current_key_state(), &handler.enter_payload);
			*effect = uint32_t(action) & allowed;
			return true;
		}
		case 2: { // Updated.
			if (!effect || handler.enter_payload.mimes.empty()) return false;
			const uint32_t allowed = *effect;
			// Availability was extracted on enter; over events only carry the MIME list.
			const jint action = handler.dispatch(2, x, y, allowed, current_key_state(), &handler.enter_payload);
			*effect = uint32_t(action) & allowed;
			return true;
		}
		case 3: { // Exited.
			const bool ours = !handler.enter_payload.mimes.empty();
			handler.enter_payload = Payload{};
			if (ours) handler.dispatch(3, 0, 0, 0, 0, nullptr);
			return true;
		}
		case 4: { // Drop.
			if (!effect || !sender) return false;
			const uint32_t allowed = *effect;
			*effect = DROPEFFECT_NONE;
			Payload payload;
			const bool extracted = extract(sender, payload, true);
			if (extracted) {
				const jint action = handler.dispatch(4, x, y, allowed, current_key_state(), &payload);
				*effect = uint32_t(action) & allowed;
			}
			handler.enter_payload = Payload{};
			return extracted;
		}
	}
	return false;
}

bool TargetHandler::handle(int kind, void *sender, int x, int y, uint32_t *effect) {
	try {
		return handle_impl(*this, kind, sender, x, y, effect);
	} catch (const std::bad_alloc &) {
	} catch (const std::length_error &) {
	}
	// Never unwind an allocation failure through the Cocoa dragging callback.
	// Consume the rejected drag instead of retrying through Godot's fallback.
	if (effect) *effect = DROPEFFECT_NONE;
	enter_payload = Payload{};
	std::fputs("JavaFX Cocoa target rejected drag: allocation failed\n", stderr);
	return true;
}

// Writes the source payload onto a pasteboard, stripping the NUL terminators
// the Java contract adds (the pasteboard conventions store raw bytes; readers
// re-terminate). File lists publish as the classic filename property list so
// path strings round-trip verbatim, like the clipboard adapter.
static void write_payload(NSPasteboard *pasteboard, const SourceData &data) {
	if (!data.text.empty()) [pasteboard setString:to_nsstring(data.text) forType:NSPasteboardTypeString];
	if (!data.url.empty()) [pasteboard setString:to_nsstring(data.url) forType:NSPasteboardTypeURL];
	if (data.html.size() > 1)
		[pasteboard setData:[NSData dataWithBytes:data.html.data() length:data.html.size() - 1] forType:@"public.html"];
	if (data.rtf.size() > 1)
		[pasteboard setData:[NSData dataWithBytes:data.rtf.data() length:data.rtf.size() - 1] forType:NSPasteboardTypeRTF];
	if (!data.files.empty()) {
		NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:data.files.size()];
		for (const std::u16string &file : data.files) [paths addObject:to_nsstring(file)];
		[pasteboard setPropertyList:paths forType:NSFilenamesPboardType];
	}
	for (const auto &entry : data.custom) {
		if (entry.second.size() < 1) continue;
		[pasteboard setData:[NSData dataWithBytes:entry.second.data() length:entry.second.size() - 1] forType:to_nsstring(custom_format::uti_type(entry.first))];
	}
}

// Builds the drag preview from the BGRA Dragboard image; nil without one.
// Pixel bytes are premultiplied and swizzled to RGBA, and the point size
// follows the window's backing scale factor.
static NSImage *drag_image(const SourceData::DragImage &image, NSWindow *window) {
	if (!image.present()) return nil;
	const size_t count = size_t(image.width) * image.height;
	if (image.bgra.size() < count * 4) return nil;
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
			initWithBitmapDataPlanes:nullptr
						  pixelsWide:image.width
						  pixelsHigh:image.height
					   bitsPerSample:8
					 samplesPerPixel:4
							hasAlpha:YES
							isPlanar:NO
					  colorSpaceName:NSDeviceRGBColorSpace
						 bytesPerRow:int(image.width) * 4
						bitsPerPixel:32];
	if (!rep) return nil;
	uint8_t *pixels = [rep bitmapData];
	for (size_t i = 0; i < count; ++i) {
		const uint8_t b = image.bgra[i * 4 + 0], g = image.bgra[i * 4 + 1], r = image.bgra[i * 4 + 2], a = image.bgra[i * 4 + 3];
		pixels[i * 4 + 0] = uint8_t((uint16_t(r) * a) / 255);
		pixels[i * 4 + 1] = uint8_t((uint16_t(g) * a) / 255);
		pixels[i * 4 + 2] = uint8_t((uint16_t(b) * a) / 255);
		pixels[i * 4 + 3] = a;
	}
	const CGFloat scale = window ? [window backingScaleFactor] : 1.0;
	NSImage *result = [[NSImage alloc] initWithSize:NSMakeSize(image.width / scale, image.height / scale)];
	if (!result) return nil;
	[result addRepresentation:rep];
	return result;
}

bool begin_source(const SourceData &data, int64_t p_window_id, void *p_ns_window, void (*done)(void *ctx, uint32_t effect), void *ctx) {
	@autoreleasepool {
		@try {
			auto *display = static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton());
			NSWindow *window = (__bridge NSWindow *)p_ns_window;
			NSView *view = window ? [window contentView] : nil;
			if (!view || !display || !display->has_window(DisplayServerEnums::WindowID(p_window_id))) return false;

			// Release Godot's per-button state before AppKit takes the mouse,
			// mirroring the Windows backend's synthetic button-up messages. The
			// Java drag session is in external mode and swallows these records.
			const NSPoint view_point = [view convertPoint:[window mouseLocationOutsideOfEventStream] fromView:nil];
			const NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
			auto release_button = [&](NSEventType type) {
				NSEvent *up = [NSEvent mouseEventWithType:type
												 location:view_point
											modifierFlags:0
												timestamp:now
											 windowNumber:[window windowNumber]
												  context:nil
											  eventNumber:0
											   clickCount:0
												 pressure:0.0];
				if (!up) return;
				if (type == NSEventTypeLeftMouseUp) [view mouseUp:up];
				else if (type == NSEventTypeRightMouseUp) [view rightMouseUp:up];
				else [view otherMouseUp:up];
			};
			if (data.buttons & 2) release_button(NSEventTypeLeftMouseUp);
			if (data.buttons & 4) release_button(NSEventTypeRightMouseUp);
			if (data.buttons & 8) release_button(NSEventTypeOtherMouseUp);

			NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
			if (!data.text.empty()) [item setString:to_nsstring(data.text) forType:NSPasteboardTypeString];
			if (!data.url.empty()) [item setString:to_nsstring(data.url) forType:NSPasteboardTypeURL];
			if (data.html.size() > 1)
				[item setData:[NSData dataWithBytes:data.html.data() length:data.html.size() - 1] forType:@"public.html"];
			if (data.rtf.size() > 1)
				[item setData:[NSData dataWithBytes:data.rtf.data() length:data.rtf.size() - 1] forType:NSPasteboardTypeRTF];
			for (const auto &entry : data.custom) {
				if (entry.second.size() < 1) continue;
				[item setData:[NSData dataWithBytes:entry.second.data() length:entry.second.size() - 1] forType:to_nsstring(custom_format::uti_type(entry.first))];
			}

			NSMutableArray<NSDraggingItem *> *items = [NSMutableArray array];
			NSImage *image = drag_image(data.image, window);
			if (!image) {
				// A dragging item must carry a visible representation; fall back
				// to the generic document icon when no Dragboard image exists.
				image = [[NSWorkspace sharedWorkspace] iconForFileType:@"public.data"];
			}
			NSSize size = [image size];
			if (size.width < 1 || size.height < 1) size = NSMakeSize(32, 32);
			// The offset is the cursor position inside the image, measured from
			// its top-left; default to the center like the Win Glass backend.
			const CGFloat ox = data.image.offset_x == INT32_MIN ? size.width / 2 : data.image.offset_x;
			const CGFloat oy = data.image.offset_y == INT32_MIN ? size.height / 2 : data.image.offset_y;
			const NSRect frame = NSMakeRect(view_point.x - ox, view_point.y - (size.height - oy), size.width, size.height);

			NSDraggingItem *drag_item = [[NSDraggingItem alloc] initWithPasteboardWriter:item];
			[drag_item setDraggingFrame:frame contents:image];
			[items addObject:drag_item];

			// Files ride as per-item NSURL writers so Finder and other
			// applications recognize the drag; the system synthesizes the
			// classic filename list on the dragging pasteboard for verbatim
			// path reads. The URLs must name existing files: cross-process
			// serialization silently drops file items whose path is missing.
			for (const std::u16string &file : data.files) {
				NSString *path = to_nsstring(file);
				NSURL *url = [NSURL fileURLWithPath:path];
				NSDraggingItem *file_drag = [[NSDraggingItem alloc] initWithPasteboardWriter:url];
				NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
				if (!icon) icon = image;
				[icon setSize:size];
				[file_drag setDraggingFrame:frame contents:icon];
				[items addObject:file_drag];
			}

			GodotJavaFXDragSource *source = [[GodotJavaFXDragSource alloc] init];
			source->allowed_effects = data.effects;
			source->done_callback = done;
			source->done_context = ctx;
			if (!g_live_sources) g_live_sources = [[NSMutableSet alloc] init];
			[g_live_sources addObject:source];

			// Queue the session onto the next real mouseDragged: AppKit only
			// tracks the physical button for sessions started inside event
			// dispatch; from this nested command context (and with a
			// synthesized event) the session ended at mouse-up without
			// dropping (destination saw DragEnter, then operation None).
			GodotJavaFXPendingDrag *pending = [[GodotJavaFXPendingDrag alloc] init];
			pending->items = items;
			pending->source = source;
			display->window_set_drag_start_handler(DisplayServerEnums::WindowID(p_window_id),
					javafx_drag_start_handler, (void *)CFBridgingRetain(pending));
			return true;
		} @catch (NSException *exception) {
			fprintf(stderr, "JavaFX drag source failed: %s\n", [[exception reason] UTF8String]);
			return false;
		}
	}
}

// Synthetic dragging info for the in-process drop test hook.
bool simulate_drop(TargetHandler &target, int x, int y, const SourceData &data) {
	@autoreleasepool {
		NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
		if (!pasteboard) return false;
		write_payload(pasteboard, data);
		// A private pasteboard may still drop file lists for nonexistent paths;
		// fall back to a serialized plist, which the reader accepts as-is.
		if (!data.files.empty() && ![pasteboard propertyListForType:NSFilenamesPboardType]) {
			NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:data.files.size()];
			for (const std::u16string &file : data.files) [paths addObject:to_nsstring(file)];
			NSData *serialized = [NSPropertyListSerialization dataWithPropertyList:paths format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
			if (serialized) [pasteboard setData:serialized forType:NSFilenamesPboardType];
		}
		GodotJavaFXDragProbe *probe = [[GodotJavaFXDragProbe alloc] init];
		probe.pasteboard = pasteboard;
		void *sender = (__bridge void *)probe;
		uint32_t enter_effect = DROPEFFECT_COPY;
		const bool entered = target.handle(1, sender, x, y, &enter_effect);
		bool dropped = false;
		if (entered) {
			uint32_t drop_effect = DROPEFFECT_COPY;
			// A rejected drop still clears the handler's enter state.
			dropped = target.handle(4, sender, x, y, &drop_effect) && drop_effect != DROPEFFECT_NONE;
		}
		return dropped;
	}
}

} // namespace godot_javafx::macos_dnd
