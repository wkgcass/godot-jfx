#pragma once

#include <CoreGraphics/CoreGraphics.h>
#include <jni.h>
#include <cstdint>
#include <vector>

// Desktop-only operations on the Java caller; never touch a Godot object.
// CoreGraphics uses global display coordinates with a top-left origin, the
// same space the Windows backend reports.
namespace godot_javafx::macos_robot {
inline void fail(JNIEnv *env, const char *type, const char *message) {
	jclass cls = env->FindClass(type);
	if (cls) { env->ThrowNew(cls, message); env->DeleteLocalRef(cls); }
}
inline void JNICALL move(JNIEnv *env, jclass, jint x, jint y) {
	CGWarpMouseCursorPosition(CGPointMake(CGFloat(x), CGFloat(y)));
}
inline jintArray JNICALL position(JNIEnv *env, jclass) {
	CGEventRef event = CGEventCreate(nullptr);
	if (!event) { fail(env, "java/lang/IllegalStateException", "Cannot read the macOS cursor"); return nullptr; }
	CGPoint point = CGEventGetLocation(event);
	CFRelease(event);
	jint values[] = { jint(point.x), jint(point.y) };
	jintArray result = env->NewIntArray(2);
	if (result) env->SetIntArrayRegion(result, 0, 2, values);
	return result;
}
inline jintArray JNICALL capture(JNIEnv *env, jclass, jint x, jint y, jint width, jint height) {
	if (width <= 0 || height <= 0 || int64_t(width) * height > 16 * 1024 * 1024 ||
			int64_t(x) + width > INT32_MAX || int64_t(y) + height > INT32_MAX) {
		fail(env, "java/lang/IllegalArgumentException", "Invalid or oversized desktop capture");
		return nullptr;
	}
	// Deprecated since macOS 14 (ScreenCaptureKit) but still functional;
	// requires screen-recording permission and returns nil without it.
	CGImageRef image = CGWindowListCreateImage(CGRectMake(CGFloat(x), CGFloat(y), CGFloat(width), CGFloat(height)),
			kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageDefault);
	if (!image) {
		fail(env, "java/lang/IllegalStateException", "macOS desktop capture failed; screen-recording permission may be missing");
		return nullptr;
	}
	std::vector<uint8_t> pixels(size_t(width) * size_t(height) * 4);
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(pixels.data(), size_t(width), size_t(height), 8, size_t(width) * 4,
			space, kCGImageAlphaPremultipliedLast);
	if (space) CFRelease(space);
	if (!context) {
		CFRelease(image);
		fail(env, "java/lang/IllegalStateException", "Cannot allocate macOS capture buffer");
		return nullptr;
	}
	CGContextDrawImage(context, CGRectMake(0, 0, CGFloat(width), CGFloat(height)), image);
	CFRelease(image);
	CFRelease(context);
	// Match the Windows robot: opaque ARGB integers in reading order.
	const jint count = width * height;
	std::vector<jint> argb((size_t(count)));
	for (jint i = 0; i < count; ++i) {
		const uint8_t *p = pixels.data() + size_t(i) * 4;
		argb[size_t(i)] = jint(0xFF000000u | (uint32_t(p[0]) << 16) | (uint32_t(p[1]) << 8) | p[2]);
	}
	jintArray result = env->NewIntArray(count);
	if (result) env->SetIntArrayRegion(result, 0, count, argb.data());
	return result;
}
}
