// lib/navigation_pipeline/pipeline_models.dart
import 'dart:ui'; // For Rect
import 'package:MAV/services/safe_path_service/zone_analyzer.dart';

import 'pipeline_constants.dart';

// Represents the combined semantic segmentation map after processing YOLO results
class SemanticSegmentationMap {
  final List<List<String>> classMap; // 160x160 grid of pipeline class names
  final int width;
  final int height;

  SemanticSegmentationMap(this.classMap, this.width, this.height);
}

// Defines a trapezoidal zone with its vertices and ID
class TrapezoidZone {
  final String id; // e.g., ZoneID.centerImmediate
  final List<Offset>
      vertices; // 4 points defining the trapezoid in 160x160 space
  // Vertices typically ordered: topLeft, topRight, bottomRight, bottomLeft

  TrapezoidZone({required this.id, required this.vertices});

  // Helper method to check if a point is inside the trapezoid
  // This is a simplified check, a more robust point-in-polygon algorithm might be needed
  bool contains(Offset point) {
    // Basic bounding box check first for efficiency
    double minX = vertices[0].dx, maxX = vertices[0].dx;
    double minY = vertices[0].dy, maxY = vertices[0].dy;
    for (int i = 1; i < vertices.length; i++) {
      minX = minX < vertices[i].dx ? minX : vertices[i].dx;
      maxX = maxX > vertices[i].dx ? maxX : vertices[i].dx;
      minY = minY < vertices[i].dy ? minY : vertices[i].dy;
      maxY = maxY > vertices[i].dy ? maxY : vertices[i].dy;
    }
    if (point.dx < minX ||
        point.dx > maxX ||
        point.dy < minY ||
        point.dy > maxY) {
      return false;
    }
    // TODO: Implement a proper point-in-trapezoid/polygon check
    // For a convex polygon like a trapezoid, one way is to check if the point
    // is on the same side of all lines formed by the edges.
    return true; // Placeholder
  }
}

// Analysis result for a single zone
class ZoneAnalysisData {
  final String zoneId;
  Map<String, double> classCoveragePercentage;
  String dominantWalkableSurface;
  double gapPercentage;
  int peopleCount;
  double closestPersonDistanceMetres;
  bool arePeopleMarginsClear;
  
  // Enhanced edge analysis
  EdgeAnalysisResult edgeAnalysis;
  
  double stairCoveragePercentage;
  bool stairsAreClear;

  // Scores
  double surfaceScore;
  double peopleClearanceScore;
  double edgeSafetyScore;
  double futureContinuityScore;
  double finalScore;

  ZoneAnalysisData({
    required this.zoneId,
    this.classCoveragePercentage = const {},
    this.dominantWalkableSurface = PipelineClasses.unknown,
    this.gapPercentage = 0.0,
    this.peopleCount = 0,
    this.closestPersonDistanceMetres = double.infinity,
    this.arePeopleMarginsClear = true,
    required this.edgeAnalysis,
    this.stairCoveragePercentage = 0.0,
    this.stairsAreClear = true,
    this.surfaceScore = 0.0,
    this.peopleClearanceScore = 0.0,
    this.edgeSafetyScore = 0.0,
    this.futureContinuityScore = 0.0,
    this.finalScore = 0.0,
  });
}

// Flutter JSON Output Structure (matches your plan)
class NavigationPipelineOutput {
  final NavigationCommand navigationCommand;
  final ZoneAnalysisOutput zoneAnalysis;
  final SafetyContext safetyContext;
  final FutureGuidance futureGuidance;
  final AccessibilityOutput accessibility;

  NavigationPipelineOutput({
    required this.navigationCommand,
    required this.zoneAnalysis,
    required this.safetyContext,
    required this.futureGuidance,
    required this.accessibility,
  });

  Map<String, dynamic> toJson() {
    return {
      "navigation_command": navigationCommand.toJson(),
      "zone_analysis": zoneAnalysis.toJson(),
      "safety_context": safetyContext.toJson(),
      "future_guidance": futureGuidance.toJson(),
      "accessibility": accessibility.toJson(),
    };
  }
}

class NavigationCommand {
  final String primaryAction; // e.g., "slight_left"
  final String targetSurface; // e.g., "footpath"
  final double confidence; // e.g., 0.87 (normalized best zone score)
  final double angleAdjustment; // e.g., 25
  final String reason; // e.g., "better_surface_available"

  NavigationCommand({
    required this.primaryAction,
    required this.targetSurface,
    required this.confidence,
    required this.angleAdjustment,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        "primary_action": primaryAction,
        "target_surface": targetSurface,
        "confidence": confidence,
        "angle_adjustment": angleAdjustment,
        "reason": reason,
      };
}

class ZoneAnalysisOutput {
  final String currentBestZoneId; // ID of the best immediate zone
  final Map<String, double> scores; // Scores for all 6 zones

  ZoneAnalysisOutput({required this.currentBestZoneId, required this.scores});

  Map<String, dynamic> toJson() => {
        "current_best": currentBestZoneId,
        "scores": scores,
      };
}

class SafetyContext {
  final PeopleDetected peopleDetected;
  final EdgeDetectionContext edgeDetection;
  final SurfaceQuality surfaceQuality;

  SafetyContext(
      {required this.peopleDetected,
      required this.edgeDetection,
      required this.surfaceQuality});

  Map<String, dynamic> toJson() => {
        "people_detected": peopleDetected.toJson(),
        "edge_detection": edgeDetection.toJson(),
        "surface_quality": surfaceQuality.toJson(),
      };
}

class PeopleDetected {
  final int count;
  final double closestDistance; // in meters
  final bool clearanceAvailable;

  PeopleDetected(
      {required this.count,
      required this.closestDistance,
      required this.clearanceAvailable});

  Map<String, dynamic> toJson() => {
        "count": count,
        "closest_distance": closestDistance,
        "clearance_available": clearanceAvailable,
      };
}

class EdgeDetectionContext {
  final List<String> footpathEdges; // e.g., ["left_detected", "right_detected"]
  final bool marginsAdequate;
  final double minimumDistanceMaintained; // in meters

  EdgeDetectionContext(
      {required this.footpathEdges,
      required this.marginsAdequate,
      required this.minimumDistanceMaintained});

  Map<String, dynamic> toJson() => {
        "footpath_edges": footpathEdges,
        "margins_adequate": marginsAdequate,
        "minimum_distance_maintained": minimumDistanceMaintained,
      };
}

class SurfaceQuality {
  final String current; // current dominant surface user is on/heading towards
  final String target; // target surface type based on best zone
  final String continuity; // e.g., "good", "changing", "ends"

  SurfaceQuality(
      {required this.current, required this.target, required this.continuity});

  Map<String, dynamic> toJson() => {
        "current": current,
        "target": target,
        "continuity": continuity,
      };
}

class FutureGuidance {
  final String lookAhead; // e.g., "footpath_continues"
  final String upcomingChanges; // e.g., "stairs_ahead"
  final String recommendedPreparation; // e.g., "prepare_for_stairs"

  FutureGuidance(
      {required this.lookAhead,
      required this.upcomingChanges,
      required this.recommendedPreparation});

  Map<String, dynamic> toJson() => {
        "look_ahead": lookAhead,
        "upcoming_changes": upcomingChanges,
        "recommended_preparation": recommendedPreparation,
      };
}

class AccessibilityOutput {
  final String voiceCommand;
  final String hapticPattern; // You'll need to define patterns
  final String audioCue; // You'll need to define cues

  AccessibilityOutput(
      {required this.voiceCommand,
      required this.hapticPattern,
      required this.audioCue});

  Map<String, dynamic> toJson() => {
        "voice_command": voiceCommand,
        "haptic_pattern": hapticPattern,
        "audio_cue": audioCue,
      };
}

// Wrapper for Yolo Results to pass to pipeline
class PipelineInputData {
  final List<dynamic> yoloResults; // ultralytics_yolo specific YOLOResult type
  final int
      imageWidth; // Original image width if needed for context, mask is 160x160
  final int imageHeight;

  PipelineInputData(
      {required this.yoloResults,
      required this.imageWidth,
      required this.imageHeight});
}
