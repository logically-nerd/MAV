// lib/navigation_pipeline/pipeline_constants.dart
import 'package:flutter/material.dart';

// Normalized class names used by the pipeline
class PipelineClasses {
  static const String road = "road";
  static const String stairs = "stairs";
  static const String footpath = "footpath";
  static const String people = "people";
  static const String nonWalkable =
      "non_walkable"; // For unclassified or unsafe areas
  static const String unknown = "unknown";
}

// Mapping from YOLO model output class names to pipeline class names
const Map<String, String> CLASS_NAME_MAPPING = {
  "roadway": PipelineClasses.road, // As per your log
  "footpath": PipelineClasses.footpath, // As per your log
  // Add other mappings if your model outputs different names for 'stairs' or 'people'
  "people": PipelineClasses.people,
  "stair": PipelineClasses.stairs, // Example
};

// Zone IDs
class ZoneID {
  static const String leftImmediate = "left_immediate";
  static const String centerImmediate = "center_immediate";
  static const String rightImmediate = "right_immediate";
  static const String leftFuture = "left_future";
  static const String centerFuture = "center_future";
  static const String rightFuture = "right_future";
}

// Navigation Actions
class NavigationAction {
  static const String continueCenter = "continue_center";
  static const String slightLeft = "slight_left";
  static const String slightRight = "slight_right";
  static const String harshLeft = "harsh_left";
  static const String harshRight = "harsh_right";
  static const String stopWait = "stop_wait";
}

// Enhanced thresholds
const double MASK_PIXEL_CONFIDENCE_THRESHOLD =
    0.5; // For sigmoid output of logits
const double GAP_SMALL_THRESHOLD_PERCENT = 0.10; // 10%
const double GAP_LARGE_THRESHOLD_PERCENT = 0.30; // 30%

// Edge-specific margins
const double SOCIAL_DISTANCE_MARGIN_METERS = 1.5;
const double FOOTPATH_EDGE_MARGIN_METERS = 0.8;
const double ROAD_EDGE_MAX_DISTANCE_METERS = 1.5;

// Patch filtering
const int MIN_PATCH_SIZE_PIXELS = 25;
const double PATCH_CONFIDENCE_THRESHOLD = 0.3;

// Center preference
const double CENTER_PREFERENCE_BONUS = 10.0;
const double SIGNIFICANT_SCORE_DIFFERENCE = 25.0;

// Scoring weights and points (as per your plan)
const double SURFACE_SCORE_WEIGHT = 0.4;
const double PEOPLE_CLEARANCE_WEIGHT = 0.3;
const double EDGE_SAFETY_WEIGHT = 0.2;
const double FUTURE_CONTINUITY_WEIGHT = 0.1;

const Map<String, int> SURFACE_PRIORITY_SCORES = {
  PipelineClasses.footpath: 100,
  PipelineClasses.road: 60,
  PipelineClasses.stairs: 40,
  PipelineClasses.nonWalkable: 0,
  PipelineClasses.unknown: 0,
};

const Map<String, int> PEOPLE_CLEARANCE_SCORES = {
  "no_people": 100,
  "people_far": 80, // > 2m
  "people_medium": 40, // 1-2m
  "people_close": 10, // < 1m
};

const int NO_EDGE_DETECTED_SCORE = 50;

// Angles for adjustments (example values)
const double ANGLE_SLIGHT = 15.0; // degrees
const double ANGLE_HARSH = 45.0; // degrees

// Dimensions of the input segmentation mask
const int MASK_WIDTH = 160;
const int MASK_HEIGHT = 160;
