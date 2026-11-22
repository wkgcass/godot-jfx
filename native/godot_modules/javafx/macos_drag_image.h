#pragma once

#import <AppKit/AppKit.h>
#include "macos_dnd.h"

namespace godot_javafx::macos_dnd {
// Builds the drag preview from the BGRA Dragboard image; nil without one.
// Pixel bytes are premultiplied and swizzled to RGBA, and the point size
// follows the window's backing scale factor.
inline NSImage *drag_image(const SourceData::DragImage &image, NSWindow *window) {
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

inline NSRect drag_frame(const SourceData::DragImage &image, NSSize size, NSPoint view_point) {
	const CGFloat ox = image.offset_x == INT32_MIN ? size.width / 2 : image.offset_x;
	const CGFloat oy = image.offset_y == INT32_MIN ? size.height / 2 : image.offset_y;
	return NSMakeRect(view_point.x - ox, view_point.y - (size.height - oy), size.width, size.height);
}
} // namespace godot_javafx::macos_dnd
