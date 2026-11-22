#import <AppKit/AppKit.h>
#include "macos_clipboard.h"
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <string>

// Exercise the native writer's ownership boundary after its Java argument has
// changed, and ensure invalid input fails before taking pasteboard ownership.
static std::u16string input = u"Godot JavaFX clipboard";
static bool exception;
static jsize JNICALL length(JNIEnv *, jstring) { return static_cast<jsize>(input.size()); }
static void JNICALL region(JNIEnv *, jstring, jsize start, jsize size, jchar *out) {
    std::copy_n(input.begin() + start, size, out);
}
static jboolean JNICALL pending(JNIEnv *) { return exception; }
static jclass JNICALL find_class(JNIEnv *, const char *) { return reinterpret_cast<jclass>(1); }
static jint JNICALL raise(JNIEnv *, jclass, const char *) { exception = true; return JNI_OK; }
static void JNICALL delete_ref(JNIEnv *, jobject) {}

int main() {
    @autoreleasepool {
        JNINativeInterface_ table{};
        table.GetStringLength = length;
        table.GetStringRegion = region;
        table.ExceptionCheck = pending;
        table.FindClass = find_class;
        table.ThrowNew = raise;
        table.DeleteLocalRef = delete_ref;
        JNIEnv env{&table};
        auto text = reinterpret_cast<jstring>(1);
        auto publish = [&] { godot_javafx::macos_clipboard::write(&env, nullptr, text, nullptr, nullptr); };
        publish();
        assert(!exception);
        auto pb = NSPasteboard.generalPasteboard;
        NSInteger count = pb.changeCount;
        input.assign({u'b', 0, u'd'});
        publish();
        assert(exception && pb.changeCount == count);
        assert([[pb stringForType:NSPasteboardTypeString] isEqualToString:@"Godot JavaFX clipboard"]);
        std::puts("COCOA_CLIPBOARD_OWNERSHIP_PASS");
    }
}
