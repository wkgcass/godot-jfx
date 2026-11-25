#pragma once
#include <jni.h>

namespace godot_javafx::wayland_robot {
void JNICALL open(JNIEnv *, jclass);
void JNICALL close(JNIEnv *, jclass);
void JNICALL button(JNIEnv *, jclass, jint, jboolean);
void JNICALL wheel(JNIEnv *, jclass, jint);
void JNICALL key(JNIEnv *, jclass, jint, jboolean);
void JNICALL move(JNIEnv *, jclass, jint, jint);
jintArray JNICALL position(JNIEnv *, jclass);
jintArray JNICALL capture(JNIEnv *, jclass, jint, jint, jint, jint);
}
