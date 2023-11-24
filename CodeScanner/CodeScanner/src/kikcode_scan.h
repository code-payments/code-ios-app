#ifndef __KIKCODE_SCAN_H__
#define __KIKCODE_SCAN_H__

#include <iostream>

#define KIK_CODE_SCAN_RESULT_SUCCESS 0
#define KIK_CODE_SCAN_RESULT_ERROR   1

#define KIK_CODE_SCAN_DEVICE_QUALITY_LOW    0
#define KIK_CODE_SCAN_DEVICE_QUALITY_MEDIUM 3
#define KIK_CODE_SCAN_DEVICE_QUALITY_HIGH   8
#define KIK_CODE_SCAN_DEVICE_QUALITY_BEST   10

extern "C" {
    int kikCodeScan(
        const unsigned char *image,
        unsigned int width,
        unsigned int height,
        unsigned int device_quality,
        unsigned char *out_data,
        unsigned int *out_x,
        unsigned int *out_y,
        unsigned int *out_scale,
        double *out_transform);
}

#endif // __KIKCODE_SCAN_H__
