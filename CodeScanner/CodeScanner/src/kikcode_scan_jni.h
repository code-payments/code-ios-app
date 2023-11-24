#ifndef _KIKCODE_SCAN_JNI_H_
#define _KIKCODE_SCAN_JNI_H_

#ifdef JNI
#include <jni.h>

extern "C" {
    jint JNI_OnLoad(JavaVM *vm, void *reserved);

    jobject Java_com_kik_scan_Scanner_scanInternal(JNIEnv *env, jobject clzz, jbyteArray image_data, jint width, jint height, jint device_quality);
}

#endif

#endif // _KIKCODE_SCAN_JNI_H_
