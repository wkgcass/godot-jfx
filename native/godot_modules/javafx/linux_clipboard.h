#pragma once
#include <jni.h>

namespace godot_javafx::wayland_clipboard {
jobjectArray JNICALL formats(JNIEnv *, jclass);
jbyteArray JNICALL read(JNIEnv *, jclass, jstring);
void JNICALL write(JNIEnv *, jclass, jobjectArray, jobjectArray);
}
