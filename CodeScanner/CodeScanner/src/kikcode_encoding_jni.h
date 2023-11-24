#ifndef _KIKCODE_ENCODING_JNI_H_
#define _KIKCODE_ENCODING_JNI_H_

#ifdef JNI
#include <jni.h>

extern "C" {
    jint JNI_OnLoad(JavaVM *vm, void *reserved);

    jobject Java_com_kik_scan_KikCode_parseInternal(JNIEnv *env, jobject clzz, jbyteArray data);

    jbyteArray Java_com_kik_scan_UsernameKikCode_encodeInternal(JNIEnv *env, jobject thiz);

    jbyteArray Java_com_kik_scan_GroupKikCode_encodeInternal(JNIEnv *env, jobject thiz);

    jbyteArray Java_com_kik_scan_RemoteKikCode_encodeInternal(JNIEnv *env, jobject thiz);
}

#endif

#endif // _KIKCODE_ENCODING_JNI_H_
