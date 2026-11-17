#include "macos_clipboard.h"

#include "macos_custom_format.h"

#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

// NSPasteboard access from the calling Java thread. No Godot Node or
// RenderingServer state is touched here. The general pasteboard is served by
// a separate system process and needs no owner window; the owner argument is
// accepted for interface parity with the Windows backend.
namespace godot_javafx::macos_clipboard {

constexpr size_t MAX_TEXT_CHARS = 16 * 1024 * 1024 / 2;
constexpr size_t MAX_PATHS = 4096;
constexpr size_t MAX_PATH_CHARS = 32768;
constexpr size_t MAX_IMAGE_DIM = 16384;

static void fail(JNIEnv *env, const char *type, const char *message) {
	jclass cls = env->FindClass(type);
	if (cls) { env->ThrowNew(cls, message); env->DeleteLocalRef(cls); }
}

static jstring to_jstring(JNIEnv *env, NSString *value) {
	if (!value) return nullptr;
	const NSUInteger length = [value length];
	if (length > MAX_TEXT_CHARS) {
		fail(env, "java/lang/IllegalStateException", "Oversized macOS pasteboard text");
		return nullptr;
	}
	std::vector<jchar> chars(length);
	if (length) [value getCharacters:reinterpret_cast<unichar *>(chars.data()) range:NSMakeRange(0, length)];
	return env->NewString(chars.data(), jsize(length));
}

// Owned copy of a Java string; reports an embedded NUL as a Java exception.
static bool from_jstring(JNIEnv *env, jstring value, NSString **out) {
	*out = nil;
	if (!value) return true;
	const jsize length = env->GetStringLength(value);
	if (size_t(length) > MAX_TEXT_CHARS) {
		fail(env, "java/lang/IllegalArgumentException", "Clipboard text exceeds 16 MiB");
		return false;
	}
	std::vector<jchar> chars((size_t(length)));
	if (length) env->GetStringRegion(value, 0, length, chars.data());
	if (env->ExceptionCheck()) return false;
	for (jsize i = 0; i < length; ++i) {
		if (chars[size_t(i)] == 0) {
			fail(env, "java/lang/IllegalArgumentException", "Clipboard text contains NUL");
			return false;
		}
	}
	*out = [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar *>(chars.data()) length:NSUInteger(length)];
	return true;
}

// Validates the Windows-shaped rich payload contract: non-empty, at most
// 16 MiB, NUL-terminated, and NUL-free otherwise. Returns the payload without
// its terminator.
static bool rich_bytes(JNIEnv *env, jbyteArray value, NSData **out) {
	*out = nil;
	if (!value) return true;
	const jsize length = env->GetArrayLength(value);
	if (length < 1 || size_t(length) > custom_format::MAX_DATA_BYTES) {
		fail(env, "java/lang/IllegalArgumentException", "Rich clipboard data must be NUL-terminated and at most 16 MiB");
		return false;
	}
	std::vector<jbyte> bytes((size_t(length)));
	env->GetByteArrayRegion(value, 0, length, bytes.data());
	if (env->ExceptionCheck()) return false;
	bool valid = bytes[size_t(length) - 1] == 0;
	for (jsize p = 0; p < length - 1; ++p) valid &= bytes[size_t(p)] != 0;
	if (!valid) {
		fail(env, "java/lang/IllegalArgumentException", "Invalid NUL in rich clipboard data");
		return false;
	}
	*out = [NSData dataWithBytes:bytes.data() length:NSUInteger(length - 1)];
	return true;
}

static NSString *rich_type(int kind) {
	return kind == 0 ? @"public.html" : @"public.rtf";
}

static void write_impl(JNIEnv *env, jstring text, jbyteArray html, jbyteArray rtf, jstring url,
		NSArray *file_paths, NSData *image_tiff, NSDictionary<NSString *, NSData *> *custom) {
	NSString *plain = nil, *link = nil;
	NSData *html_data = nil, *rtf_data = nil;
	if (!from_jstring(env, text, &plain)) return;
	if (!from_jstring(env, url, &link)) return;
	if (!rich_bytes(env, html, &html_data)) return;
	if (!rich_bytes(env, rtf, &rtf_data)) return;
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard clearContents];
	// File lists publish as the classic filename property list so the path
	// strings round-trip verbatim, like the Windows CF_HDROP backend. Routing
	// them through NSURL file objects would resolve and normalize the text.
	// Only existing paths are visible to other processes: the pasteboard
	// server drops file lists for nonexistent paths outside the writer.
	if (file_paths && [file_paths count] && ![pasteboard setPropertyList:file_paths forType:NSFilenamesPboardType]) {
		fail(env, "java/lang/IllegalStateException", "Cannot publish macOS pasteboard file list");
		return;
	}
	if (plain && ![pasteboard setString:plain forType:NSPasteboardTypeString]) {
		fail(env, "java/lang/IllegalStateException", "Cannot publish macOS pasteboard text");
		return;
	}
	if (link && ![pasteboard setString:link forType:NSPasteboardTypeURL]) {
		fail(env, "java/lang/IllegalStateException", "Cannot publish macOS pasteboard URL");
		return;
	}
	if (html_data && ![pasteboard setData:html_data forType:rich_type(0)]) {
		fail(env, "java/lang/IllegalStateException", "Cannot publish macOS pasteboard HTML");
		return;
	}
	if (rtf_data && ![pasteboard setData:rtf_data forType:rich_type(1)]) {
		fail(env, "java/lang/IllegalStateException", "Cannot publish macOS pasteboard RTF");
		return;
	}
	if (image_tiff && ![pasteboard setData:image_tiff forType:NSPasteboardTypeTIFF]) {
		fail(env, "java/lang/IllegalStateException", "Cannot publish macOS pasteboard image");
		return;
	}
	for (NSString *type in custom) {
		if (![pasteboard setData:custom[type] forType:type]) {
			fail(env, "java/lang/IllegalStateException", "Cannot publish macOS pasteboard custom format");
			return;
		}
	}
}
jstring read(JNIEnv *env, void * /*owner*/) {
	@autoreleasepool {
		return to_jstring(env, [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]);
	}
}

void write(JNIEnv *env, void *owner, jstring text, jbyteArray html, jbyteArray rtf) {
	write(env, owner, text, html, rtf, nullptr);
}

void write(JNIEnv *env, void * /*owner*/, jstring text, jbyteArray html, jbyteArray rtf, jstring url) {
	@autoreleasepool {
		write_impl(env, text, html, rtf, url, nil, nil, nil);
	}
}

jstring read_url(JNIEnv *env, void * /*owner*/) {
	@autoreleasepool {
		return to_jstring(env, [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeURL]);
	}
}

jbyteArray read_rich(JNIEnv *env, void * /*owner*/, jint kind) {
	if (kind < 0 || kind > 1) {
		fail(env, "java/lang/IllegalArgumentException", "Unknown rich clipboard format");
		return nullptr;
	}
	@autoreleasepool {
		NSData *data = [[NSPasteboard generalPasteboard] dataForType:rich_type(kind)];
		if (!data) return nullptr;
		const NSUInteger size = [data length];
		if (size < 1 || size > custom_format::MAX_DATA_BYTES) {
			fail(env, "java/lang/IllegalStateException", "Invalid rich clipboard size");
			return nullptr;
		}
		// The Java contract expects a NUL-terminated payload.
		jbyteArray result = env->NewByteArray(jsize(size + 1));
		if (result) {
			env->SetByteArrayRegion(result, 0, jsize(size), reinterpret_cast<const jbyte *>([data bytes]));
			const jbyte terminator = 0;
			env->SetByteArrayRegion(result, jsize(size), 1, &terminator);
		}
		return result;
	}
}

static NSData *encode_image(JNIEnv *env, jintArray pixels, jint width, jint height) {
	if (width < 1 || height < 1 || width > jint(MAX_IMAGE_DIM) || height > jint(MAX_IMAGE_DIM)) {
		fail(env, "java/lang/IllegalArgumentException", "Clipboard image dimensions exceed their limit");
		return nil;
	}
	if (!pixels || env->GetArrayLength(pixels) != width * height) {
		fail(env, "java/lang/IllegalArgumentException", "Clipboard image pixel count differs from its dimensions");
		return nil;
	}
	std::vector<uint8_t> rgba(size_t(width) * size_t(height) * 4);
	jint *rows = env->GetIntArrayElements(pixels, nullptr);
	if (!rows) return nil;
	for (jint i = 0; i < width * height; ++i) {
		const uint32_t argb = uint32_t(rows[i]);
		uint8_t *target = rgba.data() + size_t(i) * 4;
		target[0] = uint8_t((argb >> 16) & 0xFF);
		target[1] = uint8_t((argb >> 8) & 0xFF);
		target[2] = uint8_t(argb & 0xFF);
		target[3] = uint8_t((argb >> 24) & 0xFF);
	}
	env->ReleaseIntArrayElements(pixels, rows, JNI_ABORT);
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
			initWithBitmapDataPlanes:nullptr
						  pixelsWide:NSInteger(width)
						  pixelsHigh:NSInteger(height)
					   bitsPerSample:8
					 samplesPerPixel:4
							hasAlpha:YES
							isPlanar:NO
					  colorSpaceName:NSDeviceRGBColorSpace
						bitmapFormat:0 // 0 means alpha last (RGBA).
						 bytesPerRow:NSInteger(width) * 4
						bitsPerPixel:32];
	if (!rep) {
		fail(env, "java/lang/IllegalStateException", "Cannot allocate macOS clipboard image");
		return nil;
	}
	memcpy([rep bitmapData], rgba.data(), rgba.size());
	NSData *tiff = [rep TIFFRepresentation];
	if (!tiff) {
		fail(env, "java/lang/IllegalStateException", "Cannot encode macOS clipboard image");
		return nil;
	}
	return tiff;
}

// Validates a custom format name; returns nil (with a Java exception pending)
// or the pasteboard type for the name. Validated names are ASCII, so UTF-8
// and UTF-16 forms coincide.
static NSString *custom_type(JNIEnv *env, jstring name) {
	const jsize length = env->GetStringLength(name);
	if (size_t(length) > custom_format::MAX_NAME_CHARS) {
		fail(env, "java/lang/IllegalArgumentException", "Custom clipboard format name exceeds its limit");
		return nil;
	}
	std::u16string wide(size_t(length), 0);
	if (length) env->GetStringRegion(name, 0, length, reinterpret_cast<jchar *>(wide.data()));
	if (env->ExceptionCheck()) return nil;
	if (!custom_format::valid_name(wide)) {
		fail(env, "java/lang/IllegalArgumentException", "Custom clipboard format name outside the application/x-godot-custom- convention");
		return nil;
	}
	std::string utf8(wide.begin(), wide.end());
	return [NSString stringWithUTF8String:utf8.c_str()];
}

void write_full(JNIEnv *env, void * /*owner*/, jstring text, jbyteArray html, jbyteArray rtf, jstring url,
		jobjectArray files, jintArray image, jint image_w, jint image_h, jobjectArray custom_names, jobjectArray custom_data) {
	@autoreleasepool {
		NSMutableArray *file_paths = nil;
		if (files) {
			const jsize count = env->GetArrayLength(files);
			if (count < 1 || size_t(count) > MAX_PATHS) {
				fail(env, "java/lang/IllegalArgumentException", "Clipboard file list must hold 1..4096 paths");
				return;
			}
			file_paths = [NSMutableArray arrayWithCapacity:NSUInteger(count)];
			for (jsize i = 0; i < count; ++i) {
				auto path = reinterpret_cast<jstring>(env->GetObjectArrayElement(files, i));
				if (!path) {
					if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalArgumentException", "Clipboard file list contains null");
					return;
				}
				const jsize length = env->GetStringLength(path);
				if (length < 1 || size_t(length) > MAX_PATH_CHARS) {
					env->DeleteLocalRef(path);
					fail(env, "java/lang/IllegalArgumentException", "Clipboard file path exceeds its limit");
					return;
				}
				std::u16string value(size_t(length), 0);
				env->GetStringRegion(path, 0, length, reinterpret_cast<jchar *>(value.data()));
				env->DeleteLocalRef(path);
				if (env->ExceptionCheck()) return;
				if (value.find(u'\0') != std::u16string::npos || value.find(u'\n') != std::u16string::npos) {
					fail(env, "java/lang/IllegalArgumentException", "Invalid character in clipboard file path");
					return;
				}
				NSString *name = [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar *>(value.data()) length:NSUInteger(value.size())];
				[file_paths addObject:name];
			}
		}
		NSData *image_tiff = nil;
		if (image) {
			image_tiff = encode_image(env, image, image_w, image_h);
			if (!image_tiff) return;
		}
		NSMutableDictionary<NSString *, NSData *> *custom = nil;
		if (custom_names || custom_data) {
			const jsize count = custom_names ? env->GetArrayLength(custom_names) : 0;
			if (!custom_names || !custom_data || count != env->GetArrayLength(custom_data) ||
					size_t(count) > custom_format::MAX_FORMATS) {
				fail(env, "java/lang/IllegalArgumentException", "Custom clipboard formats require matching name/data arrays (at most 32)");
				return;
			}
			custom = [NSMutableDictionary dictionaryWithCapacity:NSUInteger(count)];
			for (jsize i = 0; i < count; ++i) {
				auto name = reinterpret_cast<jstring>(env->GetObjectArrayElement(custom_names, i));
				auto payload = reinterpret_cast<jbyteArray>(env->GetObjectArrayElement(custom_data, i));
				if (!name || !payload) {
					if (name) env->DeleteLocalRef(name);
					if (payload) env->DeleteLocalRef(payload);
					if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalArgumentException", "Custom clipboard formats contain null");
					return;
				}
				NSString *type = custom_type(env, name);
				env->DeleteLocalRef(name);
				if (!type) {
					env->DeleteLocalRef(payload);
					return;
				}
				if (custom[type]) {
					env->DeleteLocalRef(payload);
					fail(env, "java/lang/IllegalArgumentException", "Duplicate custom clipboard format");
					return;
				}
				NSData *bytes = nil;
				if (!rich_bytes(env, payload, &bytes)) {
					env->DeleteLocalRef(payload);
					return;
				}
				env->DeleteLocalRef(payload);
				custom[type] = bytes;
			}
		}
		write_impl(env, text, html, rtf, url, file_paths, image_tiff, custom);
	}
}

jbyteArray read_custom(JNIEnv *env, void * /*owner*/, jstring name) {
	@autoreleasepool {
		NSString *type = custom_type(env, name);
		if (!type) return nullptr;
		NSData *data = [[NSPasteboard generalPasteboard] dataForType:type];
		if (!data) return nullptr;
		const NSUInteger size = [data length];
		if (size < 1 || size > custom_format::MAX_DATA_BYTES) {
			fail(env, "java/lang/IllegalStateException", "Invalid custom clipboard size");
			return nullptr;
		}
		jbyteArray result = env->NewByteArray(jsize(size + 1));
		if (result) {
			env->SetByteArrayRegion(result, 0, jsize(size), reinterpret_cast<const jbyte *>([data bytes]));
			const jbyte terminator = 0;
			env->SetByteArrayRegion(result, jsize(size), 1, &terminator);
		}
		return result;
	}
}

jobjectArray custom_formats(JNIEnv *env, void * /*owner*/) {
	@autoreleasepool {
		NSArray<NSString *> *types = [[NSPasteboard generalPasteboard] types];
		std::vector<std::u16string> names;
		for (NSString *type in types) {
			const NSUInteger length = [type length];
			if (length > custom_format::MAX_NAME_CHARS) continue;
			std::u16string name(length, 0);
			if (length) [type getCharacters:reinterpret_cast<unichar *>(name.data()) range:NSMakeRange(0, length)];
			if (custom_format::valid_name(name)) {
				names.push_back(std::move(name));
				if (names.size() >= custom_format::MAX_FORMATS) break;
			}
		}
		jclass string_class = env->FindClass("java/lang/String");
		if (!string_class) return nullptr;
		jobjectArray result = env->NewObjectArray(jsize(names.size()), string_class, nullptr);
		if (result) {
			for (jsize i = 0; i < jsize(names.size()); ++i) {
				jstring name = env->NewString(reinterpret_cast<const jchar *>(names[size_t(i)].data()), jsize(names[size_t(i)].size()));
				if (!name) { env->DeleteLocalRef(string_class); return nullptr; }
				env->SetObjectArrayElement(result, i, name);
				env->DeleteLocalRef(name);
			}
		}
		env->DeleteLocalRef(string_class);
		return result;
	}
}

jobjectArray read_files(JNIEnv *env, void * /*owner*/) {
	@autoreleasepool {
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		std::vector<std::u16string> paths;
		// Classic filename list first, then modern file URLs.
		id legacy = [pasteboard propertyListForType:NSFilenamesPboardType];
		if ([legacy isKindOfClass:[NSArray class]]) {
			for (id entry in (NSArray *)legacy) {
				if (![entry isKindOfClass:[NSString class]]) continue;
				NSString *path = (NSString *)entry;
				const NSUInteger length = [path length];
				if (length > MAX_PATH_CHARS || paths.size() >= MAX_PATHS) continue;
				std::u16string value(length, 0);
				if (length) [path getCharacters:reinterpret_cast<unichar *>(value.data()) range:NSMakeRange(0, length)];
				paths.push_back(std::move(value));
			}
		} else {
			NSArray *urls = [pasteboard readObjectsForClasses:@[ [NSURL class] ] options:@{ NSPasteboardURLReadingFileURLsOnlyKey : @YES }];
			for (id entry in urls) {
				if (![entry isKindOfClass:[NSURL class]]) continue;
				NSString *path = [(NSURL *)entry path];
				if (!path) continue;
				const NSUInteger length = [path length];
				if (length > MAX_PATH_CHARS || paths.size() >= MAX_PATHS) continue;
				std::u16string value(length, 0);
				if (length) [path getCharacters:reinterpret_cast<unichar *>(value.data()) range:NSMakeRange(0, length)];
				paths.push_back(std::move(value));
			}
		}
		if (paths.empty()) return nullptr;
		jclass string_class = env->FindClass("java/lang/String");
		if (!string_class) return nullptr;
		jobjectArray result = env->NewObjectArray(jsize(paths.size()), string_class, nullptr);
		if (result) {
			for (jsize i = 0; i < jsize(paths.size()); ++i) {
				jstring path = env->NewString(reinterpret_cast<const jchar *>(paths[size_t(i)].data()), jsize(paths[size_t(i)].size()));
				if (!path) { env->DeleteLocalRef(string_class); return nullptr; }
				env->SetObjectArrayElement(result, i, path);
				env->DeleteLocalRef(path);
			}
		}
		env->DeleteLocalRef(string_class);
		return result;
	}
}

jintArray read_image(JNIEnv *env, void * /*owner*/) {
	@autoreleasepool {
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		NSData *data = nil;
		for (NSString *type in @[ NSPasteboardTypeTIFF, NSPasteboardTypePNG, @"public.jpeg", @"com.compuserve.gif", @"com.microsoft.bmp" ]) {
			data = [pasteboard dataForType:type];
			if (data) break;
		}
		if (!data) return nullptr;
		NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:data];
		if (!rep) {
			fail(env, "java/lang/IllegalStateException", "Unsupported macOS clipboard image layout");
			return nullptr;
		}
		CGImageRef cg_image = [rep CGImage];
		const size_t width = CGImageGetWidth(cg_image), height = CGImageGetHeight(cg_image);
		if (!cg_image || width < 1 || height < 1 || width > MAX_IMAGE_DIM || height > MAX_IMAGE_DIM) {
			fail(env, "java/lang/IllegalStateException", "Invalid macOS clipboard image");
			return nullptr;
		}
		std::vector<uint8_t> rgba(width * height * 4);
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		CGContextRef context = CGBitmapContextCreate(rgba.data(), width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
		if (space) CFRelease(space);
		if (!context) {
			fail(env, "java/lang/IllegalStateException", "Cannot allocate macOS clipboard image buffer");
			return nullptr;
		}
		CGContextDrawImage(context, CGRectMake(0, 0, CGFloat(width), CGFloat(height)), cg_image);
		CFRelease(context);
		jintArray result = env->NewIntArray(jsize(2 + width * height));
		if (!result) return nullptr;
		std::vector<jint> argb(2 + width * height);
		argb[0] = jint(width);
		argb[1] = jint(height);
		for (size_t i = 0; i < width * height; ++i) {
			const uint8_t *p = rgba.data() + i * 4;
			argb[2 + i] = jint((uint32_t(p[3]) << 24) | (uint32_t(p[0]) << 16) | (uint32_t(p[1]) << 8) | p[2]);
		}
		env->SetIntArrayRegion(result, 0, jsize(argb.size()), argb.data());
		return result;
	}
}

// Bit layout mirrors the Windows backend: 1 text, 2 HTML, 4 RTF, 8 URL,
// 16 files, 32 image.
jint formats() {
	@autoreleasepool {
		jint result = 0;
		NSArray<NSString *> *types = [[NSPasteboard generalPasteboard] types];
		for (NSString *type in types) {
			if ([type isEqualToString:NSPasteboardTypeString]) result |= 1;
			else if ([type isEqualToString:@"public.html"]) result |= 2;
			else if ([type isEqualToString:@"public.rtf"]) result |= 4;
			else if ([type isEqualToString:NSPasteboardTypeURL]) result |= 8;
			else if ([type isEqualToString:NSFilenamesPboardType] || [type isEqualToString:NSPasteboardTypeFileURL]) result |= 16;
			else if ([type isEqualToString:NSPasteboardTypeTIFF] || [type isEqualToString:NSPasteboardTypePNG]) result |= 32;
		}
		return result;
	}
}

} // namespace godot_javafx::macos_clipboard
