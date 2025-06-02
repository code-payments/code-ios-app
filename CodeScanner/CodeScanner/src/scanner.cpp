#include "scanner.h"
#include "kikcode_encoding.h"
#include "kikcode_constants.h"

#include <iostream>
#include <sstream>
#include <sys/time.h>

#include <opencv2/core/core.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/calib3d/calib3d.hpp>
#include <opencv2/features2d/features2d.hpp>

#define DEBUGGING 0
#define FINDER_POINT_COUNT 9

/**
 * If you are going to poke around the scanning algorithm first review the "Will it scan?"
 * presentation for an overview of the process: https://goo.gl/of0Trl
 */

using namespace std;
using namespace cv;

const uint8_t finder_bytes[] = {0xB2, 0xCB, 0x25, 0xC6};

static uint64_t getTimestamp()
{
    struct timeval now;
    gettimeofday (&now, NULL);
    return now.tv_usec + (uint64_t)now.tv_sec * 1000000;
}

#define INNER_RING_RATIO 0.32

#define START_DEBUG_TIMING(x) uint64_t __##x = getTimestamp();
#define END_DEBUG_TIMING(timing, x) if (timing) {timing->x += ((getTimestamp() - __##x) / 1000.0L);}

typedef struct {
    double dx;
    double dy;
    
    double x;
    double y;
    
    double angle;
    double dist;
    
    int contourIndex;
    int contourSize;
} FinderPoint;

bool compareFinderPointsSize(FinderPoint a, FinderPoint b)
{
    return a.contourSize < b.contourSize;
}

bool compareFinderPoints(FinderPoint a, FinderPoint b)
{
    return a.angle < b.angle;
}

void computeFinderDeltas(double *finder_deltas)
{
    const double m_pi_16 = M_PI / 16.0;

    // build the lookup table for the finder offsets in the pattern
    // the byte sequence in finder_bytes is presribed by the Kik code
    // spec and is a constant for the format
    size_t finder_starts[FINDER_POINT_COUNT];
    size_t finder_ends[FINDER_POINT_COUNT];
    bool started = false;

    int finder_offset = 0;

    for (int i = 0; i < sizeof(finder_bytes); ++i) {
        for (int j = 0; j < 8; ++j) {
            uint8_t mask = 0x1 << j;
            size_t current_offset = (i * 8) + j;

            if (mask & finder_bytes[i]) {
                if (!started) {
                    started = true;
                    finder_starts[finder_offset] = current_offset;
                }
            }
            else {
                if (started) {
                    started = false;
                    finder_ends[finder_offset++] = current_offset - 1;
                }
            }
        }
    }

    if (started) {
        finder_ends[finder_offset] = sizeof(finder_bytes) * 8 - 1;
    }

    // to find the pattern, we will look for the relative angle between blobs
    // in the finder ring, in clockwise order
    // we need to build a lookup table for these angles
    double last_offset = -1.0;

    for (int i = 0; i < sizeof(finder_starts) / sizeof(size_t); ++i) {
        double current_offset = m_pi_16 * (finder_starts[i] + finder_ends[i]) / 2.0;

        if (last_offset >= 0) {
            finder_deltas[i-1] = current_offset - last_offset;
        }

        last_offset = current_offset;
    }
}

void dilation(Mat &src, Mat &out, size_t dilation_size)
{
    Mat element = getStructuringElement(MORPH_CROSS,
                                        Size2i(2 * dilation_size + 1, 2 * dilation_size + 1),
                                        Point2i(dilation_size, dilation_size));
    
    dilate(src, out, element);
}

void unsharpMask(cv::Mat &im) 
{
    cv::Mat tmp;
    cv::GaussianBlur(im, tmp, cv::Size(0, 0), 2);
    cv::addWeighted(im, 1.5, tmp, -0.5, 0, im);
}

/**
 * For a specific, candidate ellipse, try to find the components of the orientation ring and 
 * determine the actual orientation of the code
 *
 * When this method completes, if an orientation ring was found, out_finder_points will
 * be populated with a representation of the center of each bit sequence in the finder pattern
 *
 * @returns True iff the orientation ring was present, containing the correct pattern of bits
 */
bool extractFinderPoints(int ellipse_id, bool check_high, RotatedRect inner_ring, Mat &blackish, Mat &whitish, Mat &progress, vector<FinderPoint> &out_finder_points, DebugTiming *timing, bool debug)
{
    START_DEBUG_TIMING(efp);

    START_DEBUG_TIMING(efp_compute_offset);

    double finder_deltas[FINDER_POINT_COUNT - 1];
    computeFinderDeltas(finder_deltas);

    END_DEBUG_TIMING(timing, efp_compute_offset);

    vector<FinderPoint> finder_points;

    RotatedRect finder_point_ellipse_boundaries = inner_ring;

    // start by masking off the region where we expect to find the finder
    // ring (between 1.22 and 1.525 times the size of the inner circle)
    Mat finder_point_range = Mat::zeros(whitish.size(), whitish.type());
    
    inner_ring.size.width *= 1.525;
    inner_ring.size.height *= 1.525;
    
    START_DEBUG_TIMING(efp_ellipse_region);
    ellipse(finder_point_range, inner_ring, Scalar(255, 255, 255), -1);
    
    inner_ring.size.width *= 0.805;
    inner_ring.size.height *= 0.805;
    
    ellipse(finder_point_range, inner_ring, Scalar(0, 0, 0), -1);

    if (debug) {
        char filename[128];

        sprintf(filename, "07_%d_candidates.jpg", ellipse_id);

        imwrite(filename, finder_point_range);
    }
    
    END_DEBUG_TIMING(timing, efp_ellipse_region);
    Point2i last_point;

    Mat candidate_region;

    START_DEBUG_TIMING(efp_and);

    // mask off the thresholded image to only look at the candidate region
    if (!check_high) {
        bitwise_and(blackish, finder_point_range, candidate_region);
    }
    else {
        bitwise_and(whitish, finder_point_range, candidate_region);
    }
    END_DEBUG_TIMING(timing, efp_and);

    vector<vector<Point2i> > contours;
    vector<Vec4i> hierarchy;
    
    // detect all blobs within the candidate region
    START_DEBUG_TIMING(efp_contours);
    findContours(candidate_region, contours, hierarchy, CV_RETR_CCOMP, CV_CHAIN_APPROX_SIMPLE, Point2i(0, 0));
    END_DEBUG_TIMING(timing, efp_contours);
    
    // compute the image moments for each blob in the candidate region, we use these
    // moments to look and the relative angles between the **centers** of each blob
    START_DEBUG_TIMING(efp_moments);
    vector<Moments> mu(contours.size());
    vector<Point2f> mc(contours.size());

    for (int i = 0; i < contours.size(); ++i) {
        vector<Point2i> &contour = contours[i];

        if (contour.size() > 1) {
            mu[i] = moments(contour, false);
            mc[i] = Point2f(mu[i].m10/mu[i].m00 , mu[i].m01/mu[i].m00);
        }
    }
    END_DEBUG_TIMING(timing, efp_moments);

    Mat finder_point_extraction;

    if (debug) {
        finder_point_extraction = Mat::zeros(whitish.size(), CV_8UC3);
        char filename[128];

        Mat finder_point_range = Mat::zeros(whitish.size(), CV_8UC3);

        sprintf(filename, "08_%d_finder_contours.jpg", ellipse_id);

        for (int i = 0; i < contours.size(); ++i) {
            drawContours(finder_point_range, contours, i, Scalar(rand() & 255, rand() & 255, rand() & 255), 1, 8, hierarchy, 0, Point2i());
        }

        imwrite(filename, finder_point_range);
    }

    // set up the finder point extraction process by computing the vector from the center
    // of the candidate ellipse to the center of each blob. From this vector, we care about
    // the angle and the distance from the center point
    START_DEBUG_TIMING(efp_extraction);
    for (int i = 0; i < contours.size(); ++i) {
        vector<Point2i> &contour = contours[i];
        
        Point2i point = mc[i];
        
        double dist = sqrt(pow(point.x - last_point.x, 2.0) + pow(point.y - last_point.y, 2.0));
        
        if (dist < 2) {
            continue;
        }
        
        last_point = point;
        
        if (contour.size() > 1) {
            if (mc[i].y > 0 && mc[i].x > 0) {
                if (finder_point_range.at<char>(mc[i].y, mc[i].x) != 0) {
                    FinderPoint finder;
                    
                    finder.x = mc[i].x;
                    finder.y = mc[i].y;
                    
                    finder.dx = finder.x - inner_ring.center.x;
                    finder.dy = finder.y - inner_ring.center.y;
                    
                    finder.contourIndex = i;

                    finder.contourSize = contour.size();
                    
                    finder.dist = sqrt(finder.dx * finder.dx + finder.dy * finder.dy);
                    
                    finder.angle = atan2(finder.dy, finder.dx);
                    
                    finder_points.push_back(finder);
                }
            }
        }
    }
    END_DEBUG_TIMING(timing, efp_extraction);
    
    START_DEBUG_TIMING(efp_filter_and_sort);
    if (finder_points.size() > 0) {
        // disard small shards that were erroneously picked up
        sort(finder_points.begin(), finder_points.end(), compareFinderPointsSize);

        int p90_size = finder_points[finder_points.size() * 0.9].contourSize;
        
        for (int i = 0; i < finder_points.size(); ++i) {
            if (finder_points[i].contourSize < p90_size / 5) {
                finder_points.erase(finder_points.begin() + i);

                --i;
            }
        }

        if (debug) {
            for (int i = 0; i < finder_points.size(); ++i) {
                FinderPoint finder = finder_points[i];
                Scalar colour = Scalar(rand() & 255, rand() & 255, rand() & 255);

                drawContours(finder_point_extraction, contours, finder.contourIndex, colour, 1, 8, hierarchy, 0, Point2i());
                circle(finder_point_extraction, Point2i(finder.x, finder.y), 2, colour, -1);
            }
        }
    }

    if (debug) {
        char filename[128];

        sprintf(filename, "09_%d_finder_point_extraction.jpg", ellipse_id);

        imwrite(filename, finder_point_extraction);
    }

    // if we have too few or too many finder points (we need 9), we couldn't have
    // possibly found an orientation ring
    if (finder_points.size() != sizeof(finder_deltas) / sizeof(double) + 1) {
        return false;
    }
    
    // sort the finder points into a clockwise winding based on the angle of the computed vector
    sort(finder_points.begin(), finder_points.end(), compareFinderPoints);
    END_DEBUG_TIMING(timing, efp_filter_and_sort);
    
    vector<double> point_deltas(finder_points.size());
    
    START_DEBUG_TIMING(efp_check_ratio);
    // compute the relative angles between each neighbouring pair of finder points
    for (int j = 0; j < finder_points.size(); ++j) {
        point_deltas[j] = finder_points[(j + 1) % finder_points.size()].angle - finder_points[j].angle;
        
        while (point_deltas[j] < 0.0) {
            point_deltas[j] += 2 * M_PI;
        }
    }

    int offset = -1;

    // check the relative angles against the exemplar within a +/-0.25 rad tolerance
    // find an offset such that the point deltas match the exemplar deltas relative to
    // the given starting offset
    for (int j = 0; j < point_deltas.size(); ++j) {
        bool found = true;
        
        for (int k = 0; k < sizeof(finder_deltas) / sizeof(double); ++k) {
            double pointRatio = point_deltas[(j + k) % point_deltas.size()];
            
            double lower_bound = finder_deltas[k] - 0.25;
            double upper_bound = finder_deltas[k] + 0.25;
            
            if (pointRatio < lower_bound) {
                found = false;
                break;
            }
            else if (pointRatio > upper_bound) {
                found = false;
                break;
            }
        }
        
        if (found) {
            offset = j;
            break;
        }
    }

    END_DEBUG_TIMING(timing, efp_check_ratio);
    END_DEBUG_TIMING(timing, efp);

    // if we couldn't find an offset that matches the data, we don't have a match
    if (offset < 0) {
        return false;
    }

    // we have a match! load our finder points into the output for the next step
    for (int j = 0; j < finder_points.size(); ++j) {
        out_finder_points.push_back(finder_points[(j + offset) % finder_points.size()]);
    }

    return true;
}

/**
 * Given an 8-bit, greyscale image, find an object within the image conforming to the Kik code specification.
 * We're looking for a circle, surrounded by a finder patter, surrounded by data rings, that's it.
 * 
 * If a Kik code is found, the 35 bytes contained in out_data will contain the data from the Kik code
 * that was found. That data can be decoded using other methods. Other output variables describing the scene
 * are used for debugging or aesthetic flourishes as a result of the scanning process and will be set appropriately.
 * 
 * @returns True iff a conforming Kik code has been found in the image. Note that this does not require the
 * Kik code to be properly encoded, just properly structured visually.
 */
bool detectKikCode(Mat &greyscale, Mat *out_progress, uint32_t device_quality, uint8_t *out_data, uint32_t *out_x, uint32_t *out_y, uint32_t *out_scale, Mat *transform, DebugTiming *timing, bool output_snapshots)
{
    if (timing) {
        memset(timing, 0, sizeof(DebugTiming));
    }

    // slow mode cuts down some operations and also decreases scanning results
    // but is necessary for some crumby devices
    bool in_slow_mode = device_quality < SCAN_DEVICE_QUALITY_HIGH;

    // the target buffer for the resulting scan data (if successful)
    uint8_t scan_data[KIK_CODE_BYTE_COUNT];

    START_DEBUG_TIMING(total);

    double scaling_rate = MIN(greyscale.rows, greyscale.cols) / 480.0;

    double finder_deltas[FINDER_POINT_COUNT - 1];
    computeFinderDeltas(finder_deltas);

    bool found = false;

    Mat blurry;
    Mat progress;
    Mat whitish;
    Mat blackish;

    // we switch to an inverted scheme (dark is high, light is low) if the
    // center ellipse is dark, but we don't want to compute the extra threshold everytime
    // so we only do this when necessary
    bool blackish_created = false;

    const int minimum_ellipse_contour_size = 22 * scaling_rate;
    const int ellipse_edge_tolerance = 5 * scaling_rate;
    const int adaptive_threshold_width = in_slow_mode ? 13 : 19;

    if (out_progress) {
        Mat rgb_colour;
        
        cvtColor(greyscale, rgb_colour, CV_GRAY2RGB);

        progress = rgb_colour;
    }

    START_DEBUG_TIMING(unsharp_image);

    // sharpen up the edges of our image to get more accurate blobs
    if (!in_slow_mode) {
        unsharpMask(greyscale);
        unsharpMask(greyscale);
    }

#if DEBUGGING
    if (output_snapshots) {
        imwrite("01_sharpend.jpg", greyscale);
    }
#endif

    END_DEBUG_TIMING(timing, unsharp_image);

    // determine the light vs. dark areas of the image
    START_DEBUG_TIMING(threshold);
    threshold(greyscale, whitish, 170, 255, THRESH_BINARY);
    END_DEBUG_TIMING(timing, threshold);

#if DEBUGGING
    if (output_snapshots) {
        imwrite("02_threshold.jpg", whitish);
    }
#endif

    Mat contour_mat = whitish.clone();
    
    // extract the contours and blobs from the thresholded image
    vector<vector<Point2i> > contours;
    vector<Vec4i> hierarchy;
    
    START_DEBUG_TIMING(contours_1);
    findContours(contour_mat, contours, hierarchy, CV_RETR_CCOMP, CV_CHAIN_APPROX_SIMPLE, Point2i(0, 0));
    END_DEBUG_TIMING(timing, contours_1);

#if DEBUGGING
    if (output_snapshots) {
        Mat contour_debug = Mat::zeros(greyscale.size(), CV_8UC3);

        for (int i = 0; i < contours.size(); ++i) {
            drawContours(contour_debug, contours, i, Scalar(rand() & 255, rand() & 255, rand() & 255), 1, 8, hierarchy, 0, Point2i());
        }

        imwrite("03_contours.jpg", contour_debug);
    }
#endif
    
    // compute the moments of each contour to search for large, roundish, blobs
    vector<Moments> mu(contours.size());
    vector<Point2f> mc(contours.size());
    
    START_DEBUG_TIMING(moment_pass_1);

    // find ellipses
    Mat ellipse_boundaries = Mat::zeros(contour_mat.size(), CV_8UC1);
    
    for (int i = 0; i < contours.size(); ++i) {
        vector<Point2i> &contour = contours[i];

        if (contour.size() > minimum_ellipse_contour_size) {
            mu[i] = moments(contour, false);
            mc[i] = Point2f(mu[i].m10/mu[i].m00 , mu[i].m01/mu[i].m00);
        }
    }
    END_DEBUG_TIMING(timing, moment_pass_1);

    Mat contour_selection = Mat::zeros(greyscale.size(), CV_8UC3);
    vector<vector<Point2i>> ellipse_contours;

    START_DEBUG_TIMING(ellipse_fitting_1);
    for (int i = 0; i < contours.size(); ++i) {
        vector<Point2i> &contour = contours[i];

        if (contour.size() <= minimum_ellipse_contour_size) {
            continue;
        }

        Moments moment = mu[i];
        
        // the contour must be...
        // large enough
        const double minimum_ellipse_area = 220 * scaling_rate;

        // circular enough
        const double minimum_ellipse_circularity = 0.75;

        // convex (not having a lot of concave components)
        const double minimum_ellipse_convexity = 0.9;

        // not too squished
        const double minimum_ellipse_inertia = 0.5;

        // perform checks based on the moments already computed
        double area = moment.m00;

        if (area < minimum_ellipse_area) {
#if DEBUGGING
            if (output_snapshots) {
                drawContours(contour_selection, contours, i, Scalar(0, 0, 255), 1, 8, hierarchy, 0, Point2i());
            }
#endif
            continue;
        }

        double perimeter = arcLength(Mat(contour), true);
        double circularity = 4 * CV_PI * area / (perimeter * perimeter);

        if (circularity < minimum_ellipse_circularity) {
#if DEBUGGING
            if (output_snapshots) {
                drawContours(contour_selection, contours, i, Scalar(0, 128, 255), 1, 8, hierarchy, 0, Point2i());
            }
#endif
            continue;
        }

        vector<Point> hull;
        convexHull(Mat(contour), hull);

        double hull_area = contourArea(Mat(hull));
        double convexity = area / hull_area;

        if (convexity < minimum_ellipse_convexity) {
#if DEBUGGING
            if (output_snapshots) {
                drawContours(contour_selection, contours, i, Scalar(128, 0, 255), 1, 8, hierarchy, 0, Point2i());
            }
#endif
            continue;
        }

        // compute inertia
        double denominator = sqrt(pow(2 * moment.mu11, 2) + pow(moment.mu20 - moment.mu02, 2));
        const double eps = 1e-2;

        double inertia;
        if (denominator > eps) {
            double cosmin = (moment.mu20 - moment.mu02) / denominator;
            double sinmin = 2 * moment.mu11 / denominator;
            double cosmax = -cosmin;
            double sinmax = -sinmin;

            double imin = 0.5 * (moment.mu20 + moment.mu02) - 0.5 * (moment.mu20 - moment.mu02) * cosmin - moment.mu11 * sinmin;
            double imax = 0.5 * (moment.mu20 + moment.mu02) - 0.5 * (moment.mu20 - moment.mu02) * cosmax - moment.mu11 * sinmax;

            inertia = imin / imax;
        }
        else {
            inertia = 1;
        }

        if (inertia < minimum_ellipse_inertia) {
#if DEBUGGING
            if (output_snapshots) {
                drawContours(contour_selection, contours, i, Scalar(255, 0, 255), 1, 8, hierarchy, 0, Point2i());
            }
#endif
            continue;
        }

        // all of our checks passed, looks like a potential center circle
        // fit an ellipse to the contour
//        ++timing->ellipses_fit;
        RotatedRect rect = fitEllipse(contour);

#if DEBUGGING
        if (output_snapshots) {
            drawContours(contour_selection, contours, i, Scalar(255, 0, 0), 1, 8, hierarchy, 0, Point2i());
        }
#endif

//        ++timing->ellipses_fit_matches;

        rect.size.width -= 2;
        rect.size.height -= 2;

        // track the contour that started this ellipse
        ellipse_contours.push_back(contour);

        // draw the ellipse boundaries so that we can filter out edges that do not directly
        // contribute to the main part of the elllipse (this is how we clean up issues with
        // the tail on the chat bubble)
        ellipse(ellipse_boundaries, rect, Scalar(255), ellipse_edge_tolerance);
    }

#if DEBUGGING
    if (output_snapshots) {
        imwrite("04_contour_selection.jpg", contour_selection);
    }
#endif

    END_DEBUG_TIMING(timing, ellipse_fitting_1);
    
    // only keep edges that share edges with the fitted ellipses
    Mat matches_near_ellipses;

    START_DEBUG_TIMING(and_ellipses);
    bitwise_and(whitish, ellipse_boundaries, matches_near_ellipses);
    END_DEBUG_TIMING(timing, and_ellipses);

    // filter the contours down to only the points that are within the ellipse
    // fitting tolerance (+/-2 pixels)
    vector<vector<Point2i>> pruned_contours;

    for (int i = 0; i < ellipse_contours.size(); ++i) {
        vector<Point2i> &contour = ellipse_contours[i];
        vector<Point2i> pruned_contour;

        for (int j = 0; j < contour.size(); ++j) {
            Point2i &point = contour[j];

            if (matches_near_ellipses.at<char>(point.y, point.x) != 0) {
                pruned_contour.push_back(point);
            }
        }

        pruned_contours.push_back(pruned_contour);
    }

    vector<vector<Point2i> > contours2 = pruned_contours;
    vector<Vec4i> hierarchy2;
    
    // search the limited edges to find strong ellipse matches
    vector<RotatedRect> ellipses;
    vector<size_t> contour_indices;

#if DEBUGGING
    if (output_snapshots) {
        Mat nearby_contours = Mat::zeros(greyscale.size(), CV_8UC3);

        for (int i = 0; i < contours2.size(); ++i) {
            drawContours(nearby_contours, contours2, i, Scalar(rand() & 255, rand() & 255, rand() & 255), 1, 8, hierarchy, 0, Point2i());
        }

        imwrite("05_nearby_contours.jpg", nearby_contours);
    }
#endif

    vector<RotatedRect> potential_ellipses;
    vector<size_t> potential_contour_indices;
    
    // re-fit the ellipses based on only the filtered points
    // and only if the contours have enough points to be useful
    // (ellipse fitting requires 5 reference points at a minimum)
    START_DEBUG_TIMING(ellipse_fitting_2);
    // find all ellipses in the search space by estimating the fit
    for (int i = 0; i < contours2.size(); ++i) {
        vector<Point2i> &contour = contours2[i];
        
        // the contour must be sufficiently dense
        // and the mass of the moment must be large enough
        if (contour.size() > 5) {
//            ++timing->ellipses_fit_2;
            RotatedRect rect = fitEllipse(contour);

//            ++timing->ellipses_fit_2_matches;
            potential_ellipses.push_back(rect);
            potential_contour_indices.push_back(i);
        }
    }
    END_DEBUG_TIMING(timing, ellipse_fitting_2);

    // prune the potential ellipses to avoid any ellipses that are too close in size and
    // position to other ellipses (these can occur because of the Kik code aesthetic)
    for (int i = 0; i < potential_ellipses.size(); ++i) {
        bool allowed = true;

        for (int j = i + 1; j < potential_ellipses.size(); ++j) {
            Point2i center1 = potential_ellipses[i].center;
            Point2i center2 = potential_ellipses[j].center;

            float dist = sqrt(pow(center1.x - center2.x, 2)
                       + pow(center1.y - center2.y, 2));

            if (dist < 50 && 2 * potential_ellipses[i].size.area() > potential_ellipses[j].size.area()) {
                allowed = false;
                break;
            }
        }

        if (allowed) {
            ellipses.push_back(potential_ellipses[i]);
            contour_indices.push_back(potential_contour_indices[i]);
        }
    }

//    timing->ellipse_candidates = ellipses.size();

#if DEBUGGING
    if (output_snapshots) {
        Mat candidates = Mat::zeros(greyscale.size(), CV_8UC3);

        for (int i = 0; i < ellipses.size(); ++i) {
            ellipse(candidates, ellipses[i], Scalar(255, 255, 255), 1);
        }

        imwrite("06_candidates.jpg", candidates);
    }
#endif
    
    // iterate over each candidate ring and determine if it's really the
    // center of a Kik code
    START_DEBUG_TIMING(ellipse_search);
    for (int i = 0; i < ellipses.size(); ++i) {
//        ++timing->ellipses_searched;
        RotatedRect candidate_center = ellipses[i];
        vector<FinderPoint> finder_points;
        vector<Point2i> &contour = contours2[contour_indices[i]];

        // check if this is an inverted-colour Kik code by searching the area just
        // inside the contour
        int offset = 0;
        bool check_high = true;
        bool is_region_dark = false;

        size_t dark_count = 0;

        for (int j = 0; j < contour.size(); ++j) {
            Point2i point = contour[j];
            int x = 0.9 * (point.x - candidate_center.center.x) + candidate_center.center.x;
            int y = 0.9 * (point.y - candidate_center.center.y) + candidate_center.center.y;

            if (whitish.at<char>(y, x) == 0) {
                ++dark_count;
            }
        }

        if (dark_count > 0.8 * contour.size()) {
            is_region_dark = true;
        }

        // if this is an inverted-colour code, create the dark-thresholded image if it hasn't
        // yet been created
        if (is_region_dark) {
            check_high = false;

            if (!blackish_created) {
                blackish_created = true;
                adaptiveThreshold(greyscale, blackish, 255, CV_ADAPTIVE_THRESH_MEAN_C, CV_THRESH_BINARY_INV, adaptive_threshold_width, 5);
            }
        }

        // extract the orientation ring if it is present
        if (extractFinderPoints(i, check_high, candidate_center, blackish, whitish, progress, finder_points, timing, output_snapshots)) {
            if (finder_points.size() != FINDER_POINT_COUNT) {
                continue;
            }
            
            double current_angle = M_PI / 16 - M_PI / 2;
            vector<Point2f> object_finder_points;
            vector<Point2f> scene_finder_points;

            vector<Point2f> object_corner_points;
            vector<Point2f> scene_corner_points;

            float modifier = 42;
            float offset_x = 195.0;
            float offset_y = 195.0;
            
            // create the set of scene points and object points for computing the homography to map
            // our exemplar Kik code onto the scene
            START_DEBUG_TIMING(generate_scene_points);
            for (int j = 0; j < finder_points.size(); ++j) {
                object_finder_points.push_back(
                    Point2f(modifier * 2.025 * cos(current_angle) + offset_x, modifier * 2.025 * sin(current_angle) + offset_y));
                
                current_angle += finder_deltas[j];
            }
            
            for (int j = 0; j < finder_points.size(); ++j) {
                FinderPoint point = finder_points[(j+offset) % finder_points.size()];
                scene_finder_points.push_back(Point2f(point.x, point.y));
            }
            END_DEBUG_TIMING(timing, generate_scene_points);

            try {
                // compute the homography from the object orientation ring to the scene orientation ring
                START_DEBUG_TIMING(find_homography);
                Mat H = findHomography(object_finder_points, scene_finder_points, CV_RANSAC);
                END_DEBUG_TIMING(timing, find_homography);
                
                START_DEBUG_TIMING(transform_finder_points);
                vector<Point2f> scene_corners(object_finder_points.size());
                
                perspectiveTransform(object_finder_points, scene_corners, H);
                END_DEBUG_TIMING(timing, transform_finder_points);

                START_DEBUG_TIMING(transform_all_points);
                vector<Point2f> all_points;
                vector<Point2f> scene_points;
                
                // generate all positions on the Kik code in the object space
                for (int r = 1; r < 6; ++r) {
                    size_t n = 32 + 8 * r;
                    
                    for (int j = 0; j < n; ++j) {
                        double angle = j * M_PI / n * 2 - M_PI / 2;
                        double radius = modifier * ((r + 1) * 0.4 + 1.8);
                        
                        all_points.push_back(Point2f(radius * cos(angle) + offset_x, radius * sin(angle) + offset_y));
                    }
                }
                
                // map each position in the object-space Kik code on to the scene space
                perspectiveTransform(all_points, scene_points, H);
                END_DEBUG_TIMING(timing, transform_all_points);

                START_DEBUG_TIMING(extract_data);

                // we always have the finder pattern in the first 32 bits
                memset(scan_data, 0, sizeof(scan_data));
                memcpy(scan_data, finder_bytes, sizeof(finder_bytes));
                
                // use the scene-space points to determine the data contained in the Kik code
                for (int j = 0; j < scene_points.size(); ++j) {
                    int x = (int)floor(scene_points[j].x);
                    int y = (int)floor(scene_points[j].y);

                    size_t pos = j + 32;
                    
                    // at each position, if the data is white (black in the case of inverted-colour
                    // codes), it's a 1, otherwise it's a 0
                    if (x >= 0 && y >= 0 && x < whitish.cols && y < whitish.rows) {
                        bool bit = false;

                        if (check_high) {
                            bit = whitish.at<char>(y, x) != 0;
                        }
                        else {
                            bit = blackish.at<char>(y, x) != 0;
                        }

                        if (bit) {
                            scan_data[pos/8] |= 0x1 << (pos % 8);
                        }
                    }
                }

                END_DEBUG_TIMING(timing, extract_data);

                found = true;

                // compute the inverse transform for special rendering purposes
                // (cool transitions?)
                vector<Point2f> scene_persp_points;
                vector<Point2f> object_persp_points;

                scene_persp_points.push_back(scene_corners[0]);
                object_persp_points.push_back(object_finder_points[0]);

                scene_persp_points.push_back(scene_corners[3]);
                object_persp_points.push_back(object_finder_points[3]);

                scene_persp_points.push_back(scene_corners[7]);
                object_persp_points.push_back(object_finder_points[7]);

                Mat inverse_transform = Mat::eye(3, 3, CV_64F);

                invert(H, inverse_transform);

                *out_x = (unsigned int)candidate_center.center.x;
                *out_y = (unsigned int)candidate_center.center.y;
                *out_scale = (unsigned int)(MAX(candidate_center.size.width, candidate_center.size.height) / INNER_RING_RATIO);
                *transform = inverse_transform;

#if DEBUGGING
                if (output_snapshots) {
                    Mat code_points = Mat::zeros(greyscale.size(), CV_8UC3);
                    cvtColor(greyscale, code_points, CV_GRAY2RGB);

                    for (int j = 0; j < scene_points.size(); ++j) {
                        int x = (int)floor(scene_points[j].x);
                        int y = (int)floor(scene_points[j].y);

                        bool bit = false;

                        if (x >= 0 && y >= 0 && x < whitish.cols && y < whitish.rows) {
                            if (check_high) {
                                bit = whitish.at<char>(y, x) != 0;
                            }
                            else {
                                bit = blackish.at<char>(y, x) != 0;
                            }
                        }
                        
                        if (bit) {
                            circle(code_points, Point2i(x, y), 2, Scalar(0, 0, 255), -1);
                        }
                        else {
                            circle(code_points, Point2i(x, y), 2, Scalar(255, 0, 0), -1);
                        }
                    }

                    char filename[128];

                    sprintf(filename, "10_%d_code_points.jpg", i);

                    imwrite(filename, code_points);
                }
#endif

                // we found one! We're good to go!
                break;
            }
            catch (exception &e) {
                (void)e;
            }
        }
    }
    END_DEBUG_TIMING(timing, ellipse_search);

    // if we found a code, copy over the data we recovered
    if (found) {
        memcpy(out_data, scan_data + 4, KIK_CODE_TOTAL_BYTE_COUNT);
    }

    if (out_progress != nullptr) {
        *out_progress = progress;
    }

    END_DEBUG_TIMING(timing, total);
    return found;
}

string printDebugString(DebugTiming &debug, bool include_header=false)
{
    ostringstream oss;

    if (include_header) {
        oss << "\"total\",\"unsharp_image\",\"threshold\",\"dilate\",\"contours_1\",\"moment_pass_1\",\"ellipse_fitting_1\","
            << "\"and_ellipses\",\"contours_2\",\"moment_pass_2\",\"ellipse_fitting_2\",\"ellipse_search\","
            << "\"generate_scene_points\",\"find_homography\",\"transform_finder_points\",\"transform_all_points\","
            << "\"extract_data\",\"efp\",\"efp_compute_offset\",\"efp_ellipse_region\",\"efp_and\","
            << "\"efp_contours\",\"efp_moments\",\"efp_extraction\",\"efp_filter_and_sort\",\"efp_check_ratio\","
            << "\"ellipses_fit\",\"ellipses_fit_matches\",\"ellipses_fit_2\",\"ellipses_fit_2_matches\","
            << "\"ellipse_candidates\",\"ellipses_searched\"" << endl;
    }

    oss << debug.total << ", ";
    oss << debug.unsharp_image << ", ";
    oss << debug.threshold << ", ";
    oss << debug.dilate << ", ";
    oss << debug.contours_1 << ", ";
    oss << debug.moment_pass_1 << ", ";
    oss << debug.ellipse_fitting_1 << ", ";
    oss << debug.and_ellipses << ", ";
    oss << debug.contours_2 << ", ";
    oss << debug.moment_pass_2 << ", ";
    oss << debug.ellipse_fitting_2 << ", ";
    oss << debug.ellipse_search << ", ";
    oss << debug.generate_scene_points << ", ";
    oss << debug.find_homography << ", ";
    oss << debug.transform_finder_points << ", ";
    oss << debug.transform_all_points << ", ";
    oss << debug.extract_data << ", ";
    oss << debug.efp << ", ";
    oss << debug.efp_compute_offset << ", ";
    oss << debug.efp_ellipse_region << ", ";
    oss << debug.efp_and << ", ";
    oss << debug.efp_contours << ", ";
    oss << debug.efp_moments << ", ";
    oss << debug.efp_extraction << ", ";
    oss << debug.efp_filter_and_sort << ", ";
    oss << debug.efp_check_ratio << ", ";
    oss << debug.ellipses_fit << ", ";
    oss << debug.ellipses_fit_matches << ", ";
    oss << debug.ellipses_fit_2 << ", ";
    oss << debug.ellipses_fit_2_matches << ", ";
    oss << debug.ellipse_candidates << ", ";
    oss << debug.ellipses_searched << endl;

    return oss.str();
}
