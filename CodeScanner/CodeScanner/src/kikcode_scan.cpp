#include "kikcode_scan.h"
#include "scanner.h"
#include <algorithm>
#include <opencv2/imgproc.hpp>

using namespace cv;

int kikCodeScan(
    const unsigned char *image,
    unsigned int width,
    unsigned int height,
    unsigned int device_quality,
    unsigned char *out_data,
    unsigned int *out_x,
    unsigned int *out_y,
    unsigned int *out_scale,
    double *out_transform)
{
    Mat greyscale;
    Mat transform;
    unsigned int temp_x = 0;
    unsigned int temp_y = 0;
    unsigned int temp_scale = 0;
    double scale = 0.0;

    greyscale.create(height, width, CV_8UC1);

    memcpy(greyscale.data, image, height * width);

    int max_edge_size = std::max(height, width);

    switch (device_quality) {
        case SCAN_DEVICE_QUALITY_LOW:
            if (max_edge_size > 240) {
                scale = 240.0 / max_edge_size;
            }
            break;

        case SCAN_DEVICE_QUALITY_MEDIUM:
            if (max_edge_size > 320) {
                scale = 320.0 / max_edge_size;
            }
            break;

        case SCAN_DEVICE_QUALITY_HIGH:
            if (max_edge_size > 480) {
                scale = 480.0 / max_edge_size;
            }
            break;

        case SCAN_DEVICE_QUALITY_BEST:
            if (max_edge_size > 960.0) {
                scale = 960.0 / max_edge_size;
            }
            break;

        default:
            assert(false);
    }

    if (scale > 0.0) {
        Mat sized;
        resize(greyscale, sized, Size(), scale, scale, cv::INTER_AREA);

        width = scale * width;
        height = scale * height;
        greyscale = sized;
    }

//    DebugTiming timing;
//    memset(&timing, 0, sizeof(DebugTiming));

    if (detectKikCode(greyscale, nullptr, device_quality, out_data, &temp_x, &temp_y, &temp_scale, &transform, nullptr/*&timing*/)) {
        if (out_x) {
            *out_x = temp_x;
        }
        if (out_y) {
            *out_y = temp_y;
        }
        if (out_scale) {
            *out_scale = temp_scale;
        }
        if (out_transform) {
            out_transform[0] = transform.at<double>(0, 0);
            out_transform[1] = transform.at<double>(0, 1);
            out_transform[2] = transform.at<double>(0, 2);
            out_transform[3] = transform.at<double>(1, 0);
            out_transform[4] = transform.at<double>(1, 1);
            out_transform[5] = transform.at<double>(1, 2);
            out_transform[6] = transform.at<double>(3, 0);
            out_transform[7] = transform.at<double>(3, 1);
            out_transform[8] = transform.at<double>(3, 2);
        }

        return KIK_CODE_SCAN_RESULT_SUCCESS;
    }

    return KIK_CODE_SCAN_RESULT_ERROR;
}
