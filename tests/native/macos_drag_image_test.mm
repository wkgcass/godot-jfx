#include "macos_drag_image.h"
#include <cassert>
#include <cstdio>

int main() {
    @autoreleasepool {
        using namespace godot_javafx::macos_dnd;
        SourceData::DragImage source;
        assert(!drag_image(source, nil));
        source.width = 8;
        source.height = 6;
        assert(!drag_image(source, nil));
        source.bgra.resize(8 * 6 * 4);
        source.bgra[0] = 10;
        source.bgra[1] = 40;
        source.bgra[2] = 80;
        source.bgra[3] = 128;
        NSImage *preview = drag_image(source, nil);
        assert(preview && NSEqualSizes(preview.size, NSMakeSize(8, 6)));
        NSBitmapImageRep *rep = (NSBitmapImageRep *)preview.representations.firstObject;
        const unsigned char *pixel = rep.bitmapData;
        assert(pixel && pixel[0] == 40 && pixel[1] == 20 && pixel[2] == 5 && pixel[3] == 128);
        NSPoint cursor = NSMakePoint(20, 20);
        assert(NSEqualRects(drag_frame(source, preview.size, cursor), NSMakeRect(16, 17, 8, 6)));
        source.offset_x = 5;
        source.offset_y = 1;
        assert(NSEqualRects(drag_frame(source, preview.size, cursor), NSMakeRect(15, 15, 8, 6)));
        std::puts("COCOA_DRAG_IMAGE_PASS");
    }
}
