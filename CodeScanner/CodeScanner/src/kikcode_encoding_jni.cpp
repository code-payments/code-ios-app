#include "kikcode_encoding_jni.h"
#include "kikcodes.h"
#include "kikcode_constants.h"
#include <sstream>
#include <iostream>
#include <iomanip>

using namespace std;

#ifdef JNI

extern "C" {
    jint JNI_OnLoad(JavaVM *vm, void *reserved)
    {
        JNIEnv *env;

        if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
            return -1;
        }

        return JNI_VERSION_1_6;
    }

    jobject Java_com_kik_scan_KikCode_parseInternal(JNIEnv *env, jobject clzz, jbyteArray data)
    {
        jobject decoded = nullptr;
        jbyte *buffer_ptr = env->GetByteArrayElements(data, NULL);
        unsigned int type = 0;
        unsigned int colour_code = 0;
        KikCodePayload payload;

        int result = kikCodeDecode((const unsigned char *)buffer_ptr, &type, &payload, &colour_code);

        if (result == KIK_CODE_RESULT_SUCCESS) {
            switch (type) {
            case 1: {
                jclass username_kik_code_class = env->FindClass("com/kik/scan/UsernameKikCode");
                jmethodID ctor = env->GetMethodID(username_kik_code_class, "<init>", "(Ljava/lang/String;II)V");

                jstring username_str = env->NewStringUTF(payload.username.username);

                decoded = env->NewObject(username_kik_code_class, ctor, username_str, payload.username.nonce, colour_code);
                break;
            }
            case 2: {
                jclass remote_kik_code_class = env->FindClass("com/kik/scan/RemoteKikCode");
                jmethodID ctor = env->GetMethodID(remote_kik_code_class, "<init>", "([BI)V");

                jbyteArray payload_id_bytes = env->NewByteArray(sizeof(payload.remote.payload));

                env->SetByteArrayRegion(payload_id_bytes, 0, sizeof(payload.remote.payload), (const jbyte *)payload.remote.payload);

                decoded = env->NewObject(remote_kik_code_class, ctor, payload_id_bytes, colour_code);
                break;
            }
            case 3: {
                jclass group_kik_code_class = env->FindClass("com/kik/scan/GroupKikCode");
                jmethodID ctor = env->GetMethodID(group_kik_code_class, "<init>", "([BI)V");

                jbyteArray invite_code_bytes = env->NewByteArray(sizeof(payload.group.invite_code));

                env->SetByteArrayRegion(invite_code_bytes, 0, sizeof(payload.group.invite_code), (const jbyte *)payload.group.invite_code);

                decoded = env->NewObject(group_kik_code_class, ctor, invite_code_bytes, colour_code);
                break;
            }
            }
        }
        
        env->ReleaseByteArrayElements(data, buffer_ptr, 0);

        return decoded;
    }

    jbyteArray Java_com_kik_scan_UsernameKikCode_encodeInternal(JNIEnv *env, jobject thiz)
    {
        jbyteArray result_array = nullptr;
        unsigned char out_data[KIK_CODE_TOTAL_BYTE_COUNT];

        // get UsernameKikCode class
        jclass username_kik_code_class = env->FindClass("com/kik/scan/UsernameKikCode");
        jclass kik_code_class = env->FindClass("com/kik/scan/KikCode");

        jfieldID username_field = env->GetFieldID(username_kik_code_class, "_username", "Ljava/lang/String;");
        jfieldID nonce_field = env->GetFieldID(username_kik_code_class, "_nonce", "I");
        jfieldID colour_field = env->GetFieldID(kik_code_class, "_colour", "I");

        jstring username_jstr = (jstring)env->GetObjectField(thiz, username_field);
        int nonce = env->GetIntField(thiz, nonce_field);
        int colour_code = env->GetIntField(thiz, colour_field);

        int username_length = env->GetStringUTFLength(username_jstr);
        const char *username = env->GetStringUTFChars(username_jstr, nullptr);

        // encode the username
        int result = kikCodeEncodeUsername(out_data, username, username_length, nonce, colour_code);

        // construct the results array
        if (result == KIK_CODE_RESULT_SUCCESS) {
            result_array = env->NewByteArray(sizeof(out_data));

            env->SetByteArrayRegion(result_array, 0, sizeof(out_data), (const jbyte *)out_data);
        }
        // cleanup
        env->ReleaseStringUTFChars(username_jstr, username);

        return result_array;
    }

    jbyteArray Java_com_kik_scan_GroupKikCode_encodeInternal(JNIEnv *env, jobject thiz)
    {
        jbyteArray result_array = nullptr;
        unsigned char out_data[KIK_CODE_TOTAL_BYTE_COUNT];
        unsigned char invite_code_bytes[20];

        // get GroupKikCode class
        jclass group_kik_code_class = env->FindClass("com/kik/scan/GroupKikCode");
        jclass kik_code_class = env->FindClass("com/kik/scan/KikCode");

        jfieldID invite_code_field = env->GetFieldID(group_kik_code_class, "_inviteCode", "[B");
        jfieldID colour_field = env->GetFieldID(kik_code_class, "_colour", "I");

        jbyteArray invite_code = (jbyteArray)env->GetObjectField(thiz, invite_code_field);
        int colour_code = env->GetIntField(thiz, colour_field);

        if (!invite_code) {
            return nullptr;
        }

        int length = env->GetArrayLength(invite_code);

        if (length < 20) {
            // fail if insufficient bytes have been passed through
            return nullptr;
        }

        env->GetByteArrayRegion(invite_code, 0, sizeof(invite_code_bytes), (jbyte *)invite_code_bytes);

        // encode the group code
        int result = kikCodeEncodeGroup(out_data, invite_code_bytes, colour_code);

        // construct the results array
        if (result == KIK_CODE_RESULT_SUCCESS) {
            result_array = env->NewByteArray(sizeof(out_data));

            env->SetByteArrayRegion(result_array, 0, sizeof(out_data), (const jbyte *)out_data);
        }

        return result_array;
    }

    jbyteArray Java_com_kik_scan_RemoteKikCode_encodeInternal(JNIEnv *env, jobject thiz)
    {
        jbyteArray result_array = nullptr;
        unsigned char out_data[KIK_CODE_TOTAL_BYTE_COUNT];
        unsigned char payload_id_bytes[20];

        // get RemoteKikCode class
        jclass remote_kik_code_class = env->FindClass("com/kik/scan/RemoteKikCode");
        jclass kik_code_class = env->FindClass("com/kik/scan/KikCode");

        jfieldID payload_id_field = env->GetFieldID(remote_kik_code_class, "_payloadId", "[B");
        jfieldID colour_field = env->GetFieldID(kik_code_class, "_colour", "I");

        jbyteArray payload_id = (jbyteArray)env->GetObjectField(thiz, payload_id_field);
        int colour_code = env->GetIntField(thiz, colour_field);

        if (!payload_id) {
            return nullptr;
        }

        int length = env->GetArrayLength(payload_id);

        if (length < 20) {
            // fail if insufficient bytes have been passed through
            return nullptr;
        }

        env->GetByteArrayRegion(payload_id, 0, sizeof(payload_id_bytes), (jbyte *)payload_id_bytes);

        // encode the remote code
        int result = kikCodeEncodeRemote(out_data, payload_id_bytes, colour_code);

        // construct the results array
        if (result == KIK_CODE_RESULT_SUCCESS) {
            result_array = env->NewByteArray(sizeof(out_data));

            env->SetByteArrayRegion(result_array, 0, sizeof(out_data), (const jbyte *)out_data);
        }

        return result_array;
    }
}

#endif
