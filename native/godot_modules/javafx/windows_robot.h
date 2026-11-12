#pragma once
#include <windows.h>
#include <jni.h>
#include <cstdint>

// Desktop-only operations on the Java caller; never touch a Godot object.
namespace godot_javafx::windows_robot {
inline void fail(JNIEnv *env, const char *type, const char *message) {
    jclass cls = env->FindClass(type);
    if (cls) { env->ThrowNew(cls,message); env->DeleteLocalRef(cls); }
}
inline void JNICALL move(JNIEnv *env, jclass, jint x, jint y) {
    if (!SetCursorPos(x,y)) fail(env,"java/lang/IllegalStateException","Cannot move the Windows cursor");
}
inline jintArray JNICALL position(JNIEnv *env, jclass) {
    POINT p{};
    if (!GetCursorPos(&p)) { fail(env,"java/lang/IllegalStateException","Cannot read the Windows cursor"); return nullptr; }
    jint values[] = {p.x,p.y};
    jintArray result = env->NewIntArray(2);
    if (result) env->SetIntArrayRegion(result,0,2,values);
    return result;
}
struct Capture {
    HDC screen = GetDC(nullptr);
    HDC memory = screen ? CreateCompatibleDC(screen) : nullptr;
    HBITMAP bitmap = nullptr;
    HGDIOBJ previous = nullptr;
    ~Capture() {
        if (previous && previous != HGDI_ERROR) SelectObject(memory,previous);
        if (bitmap) DeleteObject(bitmap);
        if (memory) DeleteDC(memory);
        if (screen) ReleaseDC(nullptr,screen);
    }
};
inline jintArray JNICALL capture(JNIEnv *env, jclass, jint x, jint y, jint width, jint height) {
    if (width <= 0 || height <= 0 || int64_t(width)*height > 16*1024*1024 ||
        int64_t(x)+width > INT_MAX || int64_t(y)+height > INT_MAX) {
        fail(env,"java/lang/IllegalArgumentException","Invalid or oversized desktop capture"); return nullptr;
    }
    Capture dc;
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    if (dc.memory) dc.bitmap = CreateDIBSection(dc.screen,&info,DIB_RGB_COLORS,&bits,nullptr,0);
    if (dc.bitmap) dc.previous = SelectObject(dc.memory,dc.bitmap);
    if (!dc.previous || dc.previous == HGDI_ERROR || !BitBlt(dc.memory,0,0,width,height,dc.screen,x,y,SRCCOPY|CAPTUREBLT)) {
        fail(env,"java/lang/IllegalStateException","Windows desktop capture failed"); return nullptr;
    }
    GdiFlush();
    auto *pixels = static_cast<jint *>(bits);
    const jint count = width*height;
    for (jint i=0; i<count; ++i) pixels[i] |= static_cast<jint>(0xff000000u);
    jintArray result = env->NewIntArray(count);
    if (result) env->SetIntArrayRegion(result,0,count,pixels);
    return result;
}
}
