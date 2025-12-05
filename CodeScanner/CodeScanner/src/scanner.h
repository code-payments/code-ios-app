#ifndef __SCANNER_H__
#define __SCANNER_H__

#define SCAN_DEVICE_QUALITY_LOW    0
#define SCAN_DEVICE_QUALITY_MEDIUM 3
#define SCAN_DEVICE_QUALITY_HIGH   8
#define SCAN_DEVICE_QUALITY_BEST   10

#include <iostream>

#include <opencv2/core.hpp>

typedef struct {
    double total;
    
    double unsharp_image;
    double threshold;
    double dilate;
    double contours_1;
    double moment_pass_1;
    double ellipse_fitting_1;
    double and_ellipses;
    double contours_2;
    double moment_pass_2;
    double ellipse_fitting_2;
    double ellipse_search;
    double generate_scene_points;
    double find_homography;
    double transform_finder_points;
    double transform_all_points;
    double extract_data;

    // extract finder points
    double efp;
    double efp_compute_offset;
    double efp_ellipse_region;
    double efp_and;
    double efp_contours;
    double efp_moments;
    double efp_extraction;
    double efp_filter_and_sort;
    double efp_check_ratio;

    // counting
    unsigned int ellipses_fit;
    unsigned int ellipses_fit_matches;
    unsigned int ellipses_fit_2;
    unsigned int ellipses_fit_2_matches;
    unsigned int ellipse_candidates;
    unsigned int ellipses_searched;
} DebugTiming;

std::string printDebugString(DebugTiming &debug, bool include_header);

bool detectKikCode(cv::Mat &rgb_colour, cv::Mat *out_progress, uint32_t device_quality, uint8_t *out_data, uint32_t *out_x, uint32_t *out_y, uint32_t *out_scale, cv::Mat *transform, DebugTiming *timing, bool output_snapshots=false);

#endif // __SCANNER_H__
