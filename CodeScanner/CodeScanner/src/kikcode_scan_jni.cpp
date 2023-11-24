#include "kikcode_scan_jni.h"
#include "kikcode_constants.h"

#ifdef JNI

#include "kikcode_scan.h"

extern "C" {
    jint JNI_OnLoad(JavaVM *vm, void *reserved)
    {
        JNIEnv *env;

        if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
            return -1;
        }

        return JNI_VERSION_1_6;
    }

    jobject Java_com_kik_scan_Scanner_scanInternal(JNIEnv *env, jobject clzz, jbyteArray image_data, jint width, jint height, jint device_quality)
    {
        jbyteArray result_data = nullptr;
        jbyte *buffer_ptr = env->GetByteArrayElements(image_data, NULL);

        unsigned char out_data[KIK_CODE_TOTAL_BYTE_COUNT];
        unsigned int out_x = 0;
        unsigned int out_y = 0;
        unsigned int out_scale = 0;
        double out_transform[9];

        int result = kikCodeScan((const unsigned char *)buffer_ptr, width, height, device_quality, out_data, &out_x, &out_y, &out_scale, out_transform);

        jobject scan_result = NULL;

        if (result == KIK_CODE_SCAN_RESULT_SUCCESS) {
            result_data = env->NewByteArray(sizeof(out_data));

            env->SetByteArrayRegion(result_data, 0, sizeof(out_data), (const jbyte *)out_data);

            jclass scan_result_class = env->FindClass("com/kik/scan/Scanner$ScanResult");
            jmethodID ctor = env->GetMethodID(scan_result_class, "<init>", "()V");

            scan_result = env->NewObject(scan_result_class, ctor);

            jfieldID x_field = env->GetFieldID(scan_result_class, "x", "I");
            jfieldID y_field = env->GetFieldID(scan_result_class, "y", "I");
            jfieldID scale_field = env->GetFieldID(scan_result_class, "scale", "I");
            jfieldID data_field = env->GetFieldID(scan_result_class, "data", "[B");

            env->SetIntField(scan_result, x_field, out_x);
            env->SetIntField(scan_result, y_field, out_y);
            env->SetIntField(scan_result, scale_field, out_scale);
            env->SetObjectField(scan_result, data_field, result_data);
        }

        env->ReleaseByteArrayElements(image_data, buffer_ptr, 0);

        return scan_result;
    }
}

#endif
