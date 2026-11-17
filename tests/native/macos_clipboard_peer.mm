// macOS clipboard snapshot/restore guard and external exchange peer, the
// NSPasteboard counterpart of tests/reference/ClipboardSnapshot.cs plus the
// external PowerShell peer in test-clipboard.ps1. Compiled on demand by
// scripts/test-clipboard.sh and scripts/test-clipboard-snapshot-guard.sh:
//   clang++ -std=c++17 -fobjc-arc -framework AppKit tests/native/macos_clipboard_peer.mm
//
// Modes:
//   backup <dir>                       snapshot every pasteboard type as raw
//                                      bytes plus the change count; refuses
//                                      unreadable/empty/oversized content
//                                      before any test write happens.
//   restore <dir> <expected-count>     refuse when the change count moved
//                                      (newer content preserved), otherwise
//                                      republish the snapshot byte-exactly.
//   exchange <sync-path>               external peer for ClipboardProbe:
//                                      verifies the Java rich publication,
//                                      then publishes the two external sets.
//   guard-selftest                     pure arithmetic guard checks; never
//                                      touches the system clipboard.
#import <AppKit/AppKit.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr uint64_t MAX_SNAPSHOT_BYTES = 256ULL * 1024 * 1024;

[[noreturn]] void fail(const std::string &message) {
	fprintf(stderr, "clipboard peer: %s\n", message.c_str());
	exit(1);
}

// Exact counterpart of ClipboardSnapshot.AddSnapshotBytes: bound the complete
// backup, not each format independently.
uint64_t add_snapshot_bytes(uint64_t total, uint64_t size) {
	if (total > MAX_SNAPSHOT_BYTES || size == 0 || size > MAX_SNAPSHOT_BYTES - total) {
		fail("Clipboard snapshot exceeds 256 MiB total or contains an empty block; writes refused");
	}
	return total + size;
}

// Counterpart of ClipboardSnapshot.RequireUnchanged.
void require_unchanged(int64_t expected, int64_t actual) {
	if (expected < 0 || actual < 0 || expected != actual) {
		fail("Clipboard changed or change count unavailable; newer content preserved");
	}
}

std::string utf8(NSString *value) {
	return std::string([value UTF8String] ?: "");
}

NSData *tiff_from_rgba(const uint8_t *rgba, NSInteger width, NSInteger height) {
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
			initWithBitmapDataPlanes:nullptr
						  pixelsWide:width
						  pixelsHigh:height
					   bitsPerSample:8
					 samplesPerPixel:4
							hasAlpha:YES
							isPlanar:NO
					  colorSpaceName:NSDeviceRGBColorSpace
						 bitmapFormat:0 // alpha last (RGBA)
						 bytesPerRow:width * 4
						bitsPerPixel:32];
	if (!rep) fail("Cannot allocate peer image");
	memcpy([rep bitmapData], rgba, size_t(width) * size_t(height) * 4);
	NSData *tiff = [rep TIFFRepresentation];
	if (!tiff) fail("Cannot encode peer image");
	return tiff;
}

// Decode any pasteboard image to straight ARGB words, mirroring the native
// reader in macos_clipboard.mm (premultiplied-last draw of opaque fixtures is exact).
std::vector<uint32_t> argb_pixels(NSData *data, size_t &width, size_t &height) {
	NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:data];
	if (!rep) fail("Unsupported peer clipboard image layout");
	CGImageRef image = [rep CGImage];
	width = CGImageGetWidth(image);
	height = CGImageGetHeight(image);
	if (!image || width < 1 || height < 1) fail("Invalid peer clipboard image");
	std::vector<uint8_t> rgba(width * height * 4);
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(rgba.data(), width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
	if (space) CFRelease(space);
	if (!context) fail("Cannot allocate peer image buffer");
	CGContextDrawImage(context, CGRectMake(0, 0, CGFloat(width), CGFloat(height)), image);
	CFRelease(context);
	std::vector<uint32_t> argb(width * height);
	for (size_t i = 0; i < width * height; ++i) {
		const uint8_t *p = rgba.data() + i * 4;
		argb[i] = (uint32_t(p[3]) << 24) | (uint32_t(p[0]) << 16) | (uint32_t(p[1]) << 8) | p[2];
	}
	return argb;
}

void expect(bool value, const char *reason) {
	if (!value) fail(reason);
}

std::string string_for_type(NSString *type) {
	NSString *value = [[NSPasteboard generalPasteboard] stringForType:type];
	return value ? utf8(value) : std::string();
}

NSData *data_for_type(NSString *type) {
	return [[NSPasteboard generalPasteboard] dataForType:type];
}

void expect_data(NSString *type, const std::string &expected, const char *reason) {
	NSData *data = data_for_type(type);
	expect(data != nil, reason);
	std::string actual(static_cast<const char *>([data bytes]), [data length]);
	expect(actual == expected, reason);
}

// The Java side publishes HTML in CF_HTML wire form even on macOS; validate
// the fragment through its declared byte offsets like the Windows peer does.
void expect_html_fragment(const std::string &expected) {
	NSData *data = data_for_type(@"public.html");
	expect(data != nil, "Missing native HTML clipboard format");
	std::string bytes(static_cast<const char *>([data bytes]), [data length]);
	auto offset_of = [&](const char *key) -> long {
		size_t at = bytes.find(key);
		expect(at != std::string::npos, "Invalid CF_HTML fragment header");
		return strtol(bytes.c_str() + at + strlen(key), nullptr, 10);
	};
	long start = offset_of("StartFragment:");
	long end = offset_of("EndFragment:");
	expect(start >= 1 && end >= start && size_t(end) <= bytes.size(), "Invalid CF_HTML fragment byte offsets");
	expect(bytes.substr(size_t(start), size_t(end - start)) == expected, "Native CF_HTML Unicode fragment differs");
}

void wait_for_file(const std::string &path, const char *timeout_message) {
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:35];
	while (![[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:path.c_str()]]) {
		if ([[NSDate date] compare:deadline] == NSOrderedDescending) fail(timeout_message);
		usleep(20000);
	}
}

void touch(const std::string &path) {
	if (![[NSFileManager defaultManager] createFileAtPath:[NSString stringWithUTF8String:path.c_str()]
												 contents:[NSData data] attributes:nil]) {
		fail("Cannot write peer synchronization file");
	}
}

void expect_pixels(NSData *data, size_t width, size_t height, const std::vector<uint32_t> &expected, const char *reason) {
	expect(data != nil, reason);
	size_t actual_w = 0, actual_h = 0;
	std::vector<uint32_t> actual = argb_pixels(data, actual_w, actual_h);
	expect(actual_w == width && actual_h == height && actual == expected, reason);
}

void mode_backup(const char *dir) {
	@autoreleasepool {
		NSPasteboard *pb = [NSPasteboard generalPasteboard];
		NSArray<NSString *> *types = [pb types];
		if (!types) fail("Cannot enumerate macOS pasteboard types; test writes refused");
		NSString *root = [NSString stringWithUTF8String:dir];
		NSFileManager *files = [NSFileManager defaultManager];
		if (![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]) {
			fail("Cannot create clipboard snapshot directory");
		}
		NSMutableString *manifest = [NSMutableString string];
		uint64_t total = 0;
		NSUInteger index = 0;
		for (NSString *type in types) {
			NSData *data = [pb dataForType:type];
			// A promised or unreadable type cannot be snapshotted as bytes;
			// refuse the test before any destructive write, like the Windows
			// guard refuses unknown registered formats.
			if (!data) fail("Unreadable macOS pasteboard type " + utf8(type) + "; test writes refused");
			total = add_snapshot_bytes(total, [data length]);
			[manifest appendFormat:@"%lu\t%@\n", (unsigned long)index, type];
			if (![data writeToFile:[root stringByAppendingFormat:@"/data-%lu", (unsigned long)index] atomically:NO]) {
				fail("Cannot write clipboard snapshot block");
			}
			++index;
		}
		if (![manifest writeToFile:[root stringByAppendingString:@"/manifest"] atomically:NO encoding:NSUTF8StringEncoding error:nil]) {
			fail("Cannot write clipboard snapshot manifest");
		}
		NSString *count = [NSString stringWithFormat:@"%ld", (long)[pb changeCount]];
		if (![count writeToFile:[root stringByAppendingString:@"/changecount"] atomically:NO encoding:NSUTF8StringEncoding error:nil]) {
			fail("Cannot write clipboard snapshot change count");
		}
		printf("CLIPBOARD_SNAPSHOT_CAPTURED types=%lu bytes=%llu\n", (unsigned long)index, (unsigned long long)total);
	}
}

void mode_restore(const char *dir, const char *expected_count) {
	@autoreleasepool {
		NSPasteboard *pb = [NSPasteboard generalPasteboard];
		require_unchanged(strtol(expected_count, nullptr, 10), [pb changeCount]);
		NSString *root = [NSString stringWithUTF8String:dir];
		NSString *manifest = [NSString stringWithContentsOfFile:[root stringByAppendingString:@"/manifest"]
													   encoding:NSUTF8StringEncoding error:nil];
		if (!manifest) fail("Clipboard snapshot manifest missing");
		[pb clearContents];
		NSUInteger restored = 0;
		for (NSString *line in [manifest componentsSeparatedByString:@"\n"]) {
			if ([line length] == 0) continue;
			NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
			if ([fields count] != 2) fail("Corrupt clipboard snapshot manifest");
			NSString *block = [root stringByAppendingFormat:@"/data-%@", fields[0]];
			NSData *data = [NSData dataWithContentsOfFile:block];
			if (!data || [data length] == 0) fail("Clipboard snapshot block missing");
			if (![pb setData:data forType:fields[1]]) fail("Clipboard restore publication failed");
			++restored;
		}
		// Republished bytes must read back exactly; anything else means the
		// pasteboard transformed the snapshot and the user content is lost.
		for (NSString *line in [manifest componentsSeparatedByString:@"\n"]) {
			if ([line length] == 0) continue;
			NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
			NSData *saved = [NSData dataWithContentsOfFile:[root stringByAppendingFormat:@"/data-%@", fields[0]]];
			NSData *actual = [pb dataForType:fields[1]];
			if (!actual || ![actual isEqualToData:saved]) fail("Restored clipboard bytes differ");
		}
		printf("CLIPBOARD_SNAPSHOT_RESTORED types=%lu\n", (unsigned long)restored);
	}
}

void mode_exchange(const char *sync_path) {
	@autoreleasepool {
		NSPasteboard *pb = [NSPasteboard generalPasteboard];
		std::string sync = sync_path;
		wait_for_file(sync, "Clipboard Java publication timeout");

		// Validate the rich Java publication through the same wire contracts
		// the Windows peer checks.
		expect(string_for_type(NSPasteboardTypeString) == "Godot JavaFX 中文 🙂\nsecond line", "Native text differs");
		expect_html_fragment("<b>Godot 中文 🙂</b>");
		expect_data(@"public.rtf", "{\\rtf1\\ansi Godot \\b rich\\b0}", "Native RTF differs");
		expect(string_for_type(NSPasteboardTypeURL) == "https://example.invalid/中文?q=🙂", "Native URL Unicode value differs");
		id files = [pb propertyListForType:NSFilenamesPboardType];
		expect([files isKindOfClass:[NSArray class]] && [(NSArray *)files count] == 2
				&& [((NSArray *)files)[0] isEqualToString:@"/tmp/godot-jfx-clipboard-fixture/godot-jfx测试/报告 🙂.txt"]
				&& [((NSArray *)files)[1] isEqualToString:@"/tmp/godot-jfx-clipboard-fixture/README.md"],
				"Native file list differs");
		expect_pixels(data_for_type(NSPasteboardTypeTIFF), 3, 2,
				{ 0xFF0A141E, 0xFF28323C, 0xFF46505A, 0xFF646E78, 0xFF828C96, 0x00000000 }, "Native image pixels differ");
		expect_data(@"application/x-godot-custom-token", "剪贴板自定义负载 🙂", "Custom clipboard payload differs");

		// First external set: text, Unicode URL, CF_HTML fragment and RTF.
		NSString *prefix = @"<html><body><!--StartFragment-->";
		NSString *fragment = @"<i>External 中文 🙂</i>";
		NSString *suffix = @"<!--EndFragment--></body></html>";
		NSString *skeleton = @"Version:1.0\r\nStartHTML:0000000000\r\nEndHTML:0000000000\r\nStartFragment:0000000000\r\nEndFragment:0000000000\r\n";
		NSUInteger start_html = [skeleton lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		NSUInteger start_fragment = start_html + [prefix lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		NSUInteger end_fragment = start_fragment + [fragment lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		NSUInteger end_html = end_fragment + [suffix lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		NSString *html = [NSString stringWithFormat:
				@"Version:1.0\r\nStartHTML:%010lu\r\nEndHTML:%010lu\r\nStartFragment:%010lu\r\nEndFragment:%010lu\r\n%@%@%@",
				(unsigned long)start_html, (unsigned long)end_html,
				(unsigned long)start_fragment, (unsigned long)end_fragment, prefix, fragment, suffix];
		[pb clearContents];
		[pb setString:@"Godot external 中文 🙂" forType:NSPasteboardTypeString];
		[pb setString:@"https://external.invalid/目录#🙂" forType:NSPasteboardTypeURL];
		[pb setData:[html dataUsingEncoding:NSUTF8StringEncoding] forType:@"public.html"];
		[pb setData:[@"{\\rtf1\\ansi External \\i rich\\i0}" dataUsingEncoding:NSUTF8StringEncoding] forType:@"public.rtf"];
		printf("CLIPBOARD_CHANGE_COUNT %ld\n", (long)[pb changeCount]);
		touch(sync + ".external");
		wait_for_file(sync + ".ack", "Clipboard Java acknowledgement timeout");

		// Second set: raw file list + opaque 24bpp-equivalent image + URL +
		// custom payload, deliberately without any text format.
		[pb clearContents];
		if (![pb setPropertyList:@[ @"/tmp/godot-jfx-clipboard-fixture/外部/文件 甲.txt", @"/tmp/godot-jfx-clipboard-fixture/外部/乙🙂.png" ] forType:NSFilenamesPboardType]) {
			fail("Cannot publish external file list");
		}
		const uint8_t rgba[16] = { 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
		[pb setData:tiff_from_rgba(rgba, 2, 2) forType:NSPasteboardTypeTIFF];
		[pb setString:@"https://ansi.invalid/中文路径" forType:NSPasteboardTypeURL];
		[pb setData:[@"外部剪贴板负载 🙂" dataUsingEncoding:NSUTF8StringEncoding]
			forType:@"application/x-godot-custom-token"];
		printf("CLIPBOARD_CHANGE_COUNT %ld\n", (long)[pb changeCount]);
		touch(sync + ".external2");
		printf("CLIPBOARD_EXTERNAL_RICH_PASS\n");
	}
}

// Pure arithmetic counterparts of the Windows snapshot guard checks; this
// mode never opens the system clipboard.
void mode_guard_selftest() {
	if (add_snapshot_bytes(0, 1) != 1) fail("Small snapshot accounting differs");
	if (add_snapshot_bytes(MAX_SNAPSHOT_BYTES - 1, 1) != MAX_SNAPSHOT_BYTES) fail("Exact snapshot budget refused");
	const uint64_t budget_cases[][2] = { {0, 0}, {MAX_SNAPSHOT_BYTES, 1}, {MAX_SNAPSHOT_BYTES - 1, 2}, {UINT64_MAX, 1}, {0, UINT64_MAX} };
	for (const auto &pair : budget_cases) {
		// add_snapshot_bytes exits the process on refusal, so probe via the
		// same predicate the function guards with.
		bool rejected = pair[0] > MAX_SNAPSHOT_BYTES || pair[1] == 0 || pair[1] > MAX_SNAPSHOT_BYTES - pair[0];
		if (!rejected) fail("Invalid aggregate clipboard size accepted");
	}
	printf("CLIPBOARD_SNAPSHOT_BUDGET_PASS (no clipboard access)\n");
	require_unchanged(42, 42);
	const int64_t sequence_cases[][2] = { {42, 43}, {-1, -1}, {42, -1}, {-1, 42} };
	for (const auto &pair : sequence_cases) {
		bool rejected = pair[0] < 0 || pair[1] < 0 || pair[0] != pair[1];
		if (!rejected) fail("Changed or unavailable clipboard sequence accepted");
	}
	printf("CLIPBOARD_SNAPSHOT_GUARD_PASS (no clipboard access)\n");
}

} // namespace

int main(int argc, char **argv) {
	if (argc < 2) fail("usage: macos_clipboard_peer backup <dir> | restore <dir> <count> | exchange <sync> | guard-selftest");
	std::string mode = argv[1];
	if (mode == "backup" && argc == 3) { mode_backup(argv[2]); return 0; }
	if (mode == "restore" && argc == 4) { mode_restore(argv[2], argv[3]); return 0; }
	if (mode == "exchange" && argc == 3) { mode_exchange(argv[2]); return 0; }
	if (mode == "guard-selftest" && argc == 2) { mode_guard_selftest(); return 0; }
	fail("unknown mode");
}
