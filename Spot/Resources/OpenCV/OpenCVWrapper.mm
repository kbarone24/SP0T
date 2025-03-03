//
//  OpenCVWrapper.m
//  Spot
//
//  Created by Kenny Barone on 3/1/21.
//  Copyright © 2021 sp0t, LLC. All rights reserved.
//

#include "OpenCVWrapper.h"
#import "UIImage+OpenCV.h"

#include <opencv2/opencv.hpp>
#include <opencv2/imgproc/imgproc_c.h>
#include <opencv2/core/types_c.h>

using namespace cv;
using namespace std;

const int SMOOTHING_RADIUS = 10; // In frames. The larger the more stable the video, but less reactive to sudden panning

struct TransformParam {
    TransformParam() {}
    TransformParam(double _dx, double _dy, double _da) {
        dx = _dx;
        dy = _dy;
        da = _da;
    }

    double dx, dy, da;
};

struct Trajectory {
    Trajectory() {}
    Trajectory(double _x, double _y, double _a) {
        x = _x;
        y = _y;
        a = _a;
    }

    double x, y, a;
};

@implementation OpenCVWrapper : NSObject

+ (NSURL *)processVideoFileWithOpenCV:(NSURL*)url : (NSURL*)result {

    String file = *new String(url.path.UTF8String);
    String resultFile = *new String(result.path.UTF8String);

    VideoCapture cap(file);

    assert(cap.isOpened());

    Mat cur, cur_grey, cur_orig;
    Mat prev, prev_grey, prev_orig;

    cap >> prev;
    cvtColor(prev, prev_grey, COLOR_BGR2GRAY);

    // Step 1 - Get previous to current frame transformation (dx, dy, da) for all frames
    vector <TransformParam> prev_to_cur_transform; // previous to current

    int frames=1;
    int max_frames = cap.get(CAP_PROP_FRAME_COUNT);
    cout << max_frames;
    Mat last_T;

    while(true) {
        cap >> cur;

        if(cur.data == NULL) {
            break;
        }

        cvtColor(cur, cur_grey, COLOR_BGR2GRAY);

        // vector from prev to cur
        vector <Point2f> prev_corner, cur_corner;
        vector <Point2f> prev_corner2, cur_corner2;
        vector <uchar> status;
        vector <float> err;

        goodFeaturesToTrack(prev_grey, prev_corner, 200, 0.01, 30);
        calcOpticalFlowPyrLK(prev_grey, cur_grey, prev_corner, cur_corner, status, err);

        // weed out bad matches
        for(size_t i=0; i < status.size(); i++) {
            if(status[i]) {
                prev_corner2.push_back(prev_corner[i]);
                cur_corner2.push_back(cur_corner[i]);

                cv::line(cur, prev_corner[i], cur_corner[i], CV_RGB(255,0,0), 1, CV_AA); // DEBUGGING ONLY
            }
        }

        // translation + rotation only
        Mat T = estimateAffine2D(prev_corner, cur_corner);
     //   Mat T = estimateRigidTransform(prev_corner, cur_corner, true); // false = rigid transform, no scaling/shearing

        // in rare cases no transform is found. We'll just use the last known good transform.
        if(T.data == NULL) {
            last_T.copyTo(T);
        }

        T.copyTo(last_T);

        // decompose T
        double dx = T.at<double>(0,2);
        double dy = T.at<double>(1,2);
        double da = atan2(T.at<double>(1,0), T.at<double>(0,0));

        prev_to_cur_transform.push_back(TransformParam(dx, dy, da));

        cur.copyTo(prev);
        cur_grey.copyTo(prev_grey);

        frames++;
    }

    // Step 2 - Accumulate the transformations to get the image trajectory

    // Accumulated frame to frame transform
    double a = 0;
    double x = 0;
    double y = 0;

    vector <Trajectory> trajectory; // trajectory at all frames

    for(size_t i=0; i < prev_to_cur_transform.size(); i++) {
        x += prev_to_cur_transform[i].dx;
        y += prev_to_cur_transform[i].dy;
        a += prev_to_cur_transform[i].da;

        trajectory.push_back(Trajectory(x,y,a));
    }

    // Step 3 - Smooth out the trajectory using an averaging window
    vector <Trajectory> smoothed_trajectory; // trajectory at all frames

    for(size_t i=0; i < trajectory.size(); i++) {
        double sum_x = 0;
        double sum_y = 0;
        double sum_a = 0;
        int count = 0;

        for(int j=-SMOOTHING_RADIUS; j <= SMOOTHING_RADIUS; j++) {
            if(i+j >= 0 && i+j < trajectory.size()) {
                sum_x += trajectory[i+j].x;
                sum_y += trajectory[i+j].y;
                sum_a += trajectory[i+j].a;

                count++;
            }
        }

        double avg_a = sum_a / count;
        double avg_x = sum_x / count;
        double avg_y = sum_y / count;

        smoothed_trajectory.push_back(Trajectory(avg_x, avg_y, avg_a));
    }

    // Step 4 - Generate new set of previous to current transform, such that the trajectory ends up being the same as the smoothed trajectory
    vector <TransformParam> new_prev_to_cur_transform;

    // Accumulated frame to frame transform
    a = 0;
    x = 0;
    y = 0;

    for(size_t i=0; i < prev_to_cur_transform.size(); i++) {
        x += prev_to_cur_transform[i].dx;
        y += prev_to_cur_transform[i].dy;
        a += prev_to_cur_transform[i].da;

        // target - current
        double diff_x = smoothed_trajectory[i].x - x;
        double diff_y = smoothed_trajectory[i].y - y;
        double diff_a = smoothed_trajectory[i].a - a;
        
        double dx = prev_to_cur_transform[i].dx + diff_x;
        double dy = prev_to_cur_transform[i].dy + diff_y;
        double da = prev_to_cur_transform[i].da + diff_a;

        new_prev_to_cur_transform.push_back(TransformParam(dx, dy, da));
    }

    // Step 5 - Apply the new transformation to the video
    cap.set(CAP_PROP_POS_FRAMES, 0);

    double width = prev.size().width;
    double height = prev.size().height;
    Mat T(2,3,CV_64F);

    int ex = static_cast<int>(cap.get(CAP_PROP_FOURCC));     // Get Codec Type- Int form

    VideoWriter writer(resultFile, ex, 12, cv::Size(width,height), true);  /// 12 = 12 fps
    
    //writer.open(resultFile, VideoWriter::fourcc('M','J','P','G'), 30, cv::Size(width, height));

    if (!writer.isOpened()) {
        cout << "Could not open file for writing";
    }

    int k=0;
    cap.release();

    VideoCapture cap2(file);

    assert(cap2.isOpened());

    while(k < frames-1) { // don't process the very last frame, no valid transform
        cap2 >> cur;

        if(cur.data == NULL) {
            break;
        }

        T.at<double>(0,0) = cos(new_prev_to_cur_transform[k].da);
        T.at<double>(0,1) = -sin(new_prev_to_cur_transform[k].da);
        T.at<double>(1,0) = sin(new_prev_to_cur_transform[k].da);
        T.at<double>(1,1) = cos(new_prev_to_cur_transform[k].da);

        T.at<double>(0,2) = new_prev_to_cur_transform[k].dx;
        T.at<double>(1,2) = new_prev_to_cur_transform[k].dy;

        Mat cur2;

        warpAffine(cur, cur2, T, cur.size());

        // Resize cur2 back to cur size, for better side by side comparison
        resize(cur2, cur2, cur.size());

        double diffx = width * 0.2;
        double diffy = height * 0.2;

        cv::Rect myROI((diffx/2),(diffy/2),width-(diffx),height-(diffy));

        Mat fin = cur2(myROI);

        resize(fin, fin, cur2.size());

        writer.write(fin);

        k++;
    }
    
    writer.release();
    cout << "Video Stabilisation complete";
    return result;
}

@end

///https://answers.opencv.org/question/82304/how-to-use-videostabcpp-in-a-swift-program/
