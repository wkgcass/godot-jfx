#pragma once

#include <jni.h>

// NSPasteboard adapter behind the same Java-facing contract as
// windows_clipboard.h. The implementation lives in macos_clipboard.mm
// (Objective-C); the owner handle is accepted for interface parity and is
// unused because the general pasteboard needs no owner window.
namespace godot_javafx::macos_clipboard {
jstring read(JNIEnv *env, void *owner);
void write(JNIEnv *env, void *owner, jstring text, jbyteArray html, jbyteArray rtf);
void write(JNIEnv *env, void *owner, jstring text, jbyteArray html, jbyteArray rtf, jstring url);
jstring read_url(JNIEnv *env, void *owner);
jbyteArray read_rich(JNIEnv *env, void *owner, jint kind);
void write_full(JNIEnv *env, void *owner, jstring text, jbyteArray html, jbyteArray rtf, jstring url,
		jobjectArray files, jintArray image, jint image_w, jint image_h, jobjectArray custom_names, jobjectArray custom_data);
jbyteArray read_custom(JNIEnv *env, void *owner, jstring name);
jobjectArray custom_formats(JNIEnv *env, void *owner);
jobjectArray read_files(JNIEnv *env, void *owner);
jintArray read_image(JNIEnv *env, void *owner);
jint formats();
}
