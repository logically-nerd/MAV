// lib/navigation_pipeline/zone_analyzer.dart
import 'dart:math';
import 'pipeline_models.dart';
import 'dart:ui';
import 'pipeline_constants.dart';
import 'calibration_service.dart';
import 'decision_engine.dart';

class ZoneAnalyzer {
  static const double MIN_EDGE_DISTANCE_FOOTPATH = 1.5; // meters
  static const double MAX_DISTANCE_FROM_ROAD_EDGE = 1.5; // meters

  static ZoneAnalysisData analyzeZone(TrapezoidZone zone,
      SemanticSegmentationMap semanticMap, List<dynamic> rawYoloResults) {
    print("ZONE_ANALYZER: Analyzing zone ${zone.id}");
    Map<String, int> classPixelCounts = {};
    int totalPixelsInZone = 0;

    // Initialize class pixel counts
    ([...SURFACE_PRIORITY_SCORES.keys, PipelineClasses.people])
        .forEach((cls) => classPixelCounts[cls] = 0);

    // Get zone bounds
    double minX = zone.vertices.map((v) => v.dx).reduce(min);
    double maxX = zone.vertices.map((v) => v.dx).reduce(max);
    double minY = zone.vertices.map((v) => v.dy).reduce(min);
    double maxY = zone.vertices.map((v) => v.dy).reduce(max);

    // Count pixels within trapezoid
    for (int r = max(0, minY.floor());
        r < min(semanticMap.height, maxY.ceil());
        r++) {
      for (int c = max(0, minX.floor());
          c < min(semanticMap.width, maxX.ceil());
          c++) {
        if (zone.contains(Offset(c.toDouble() + 0.5, r.toDouble() + 0.5))) {
          totalPixelsInZone++;
          String pixelClass = semanticMap.classMap[r][c];
          classPixelCounts[pixelClass] =
              (classPixelCounts[pixelClass] ?? 0) + 1;
        }
      }
    }

    Map<String, double> classCoveragePercentage = {};
    if (totalPixelsInZone > 0) {
      classPixelCounts.forEach((key, value) {
        classCoveragePercentage[key] = value / totalPixelsInZone;
      });
    } else {
      ([...SURFACE_PRIORITY_SCORES.keys, PipelineClasses.people])
          .forEach((cls) => classCoveragePercentage[cls] = 0.0);
    }

    // Find dominant walkable surface
    String dominantWalkableSurface = PipelineClasses.unknown;
    double maxWalkableCoverage = -1.0;
    SURFACE_PRIORITY_SCORES.keys
        .where((k) =>
            k != PipelineClasses.nonWalkable && k != PipelineClasses.unknown)
        .forEach((cls) {
      double coverage = classCoveragePercentage[cls] ?? 0.0;
      if (coverage > maxWalkableCoverage) {
        maxWalkableCoverage = coverage;
        dominantWalkableSurface = cls;
      } else if (coverage == maxWalkableCoverage && coverage > 0) {
        if ((SURFACE_PRIORITY_SCORES[cls] ?? 0) >
            (SURFACE_PRIORITY_SCORES[dominantWalkableSurface] ?? 0)) {
          dominantWalkableSurface = cls;
        }
      }
    });

    if (maxWalkableCoverage == 0 &&
        (classCoveragePercentage[PipelineClasses.nonWalkable] ?? 0.0) > 0) {
      dominantWalkableSurface = PipelineClasses.nonWalkable;
    }

    // Calculate gap percentage
    double walkableCoverageSum =
        (classCoveragePercentage[PipelineClasses.footpath] ?? 0.0) +
            (classCoveragePercentage[PipelineClasses.road] ?? 0.0) +
            (classCoveragePercentage[PipelineClasses.stairs] ?? 0.0);
    double gapPercentage = 1.0 -
        walkableCoverageSum -
        (classCoveragePercentage[PipelineClasses.people] ?? 0.0);
    gapPercentage = max(0, gapPercentage);

    // People detection (simplified)
    int peopleCountInZone = classPixelCounts[PipelineClasses.people] ?? 0;
    double closestPersonDist = double.infinity;
    bool peopleMarginsClear = true;

    // Enhanced edge detection
    EdgeAnalysisResult edgeAnalysis = _analyzeZoneEdges(zone, semanticMap);

    // Stairs analysis
    double stairCoverage =
        classCoveragePercentage[PipelineClasses.stairs] ?? 0.0;
    bool stairsClear = true;

    print(
        "ZONE_ANALYZER: Zone ${zone.id} - Dominant: $dominantWalkableSurface, People Pixels: $peopleCountInZone, Gap: $gapPercentage");

    ZoneAnalysisData zoneData = ZoneAnalysisData(
      zoneId: zone.id,
      classCoveragePercentage: classCoveragePercentage,
      dominantWalkableSurface: dominantWalkableSurface,
      gapPercentage: gapPercentage,
      peopleCount: peopleCountInZone,
      closestPersonDistanceMetres: closestPersonDist,
      arePeopleMarginsClear: peopleMarginsClear,
      stairCoveragePercentage: stairCoverage,
      stairsAreClear: stairsClear,
      edgeAnalysis: edgeAnalysis,
    );

    DecisionEngine.calculateIntermediateScores(zoneData);
    return zoneData;
  }

  static EdgeAnalysisResult _analyzeZoneEdges(
      TrapezoidZone zone, SemanticSegmentationMap semanticMap) {
    // Get zone bounds
    double minX = zone.vertices.map((v) => v.dx).reduce(min);
    double maxX = zone.vertices.map((v) => v.dx).reduce(max);
    double minY = zone.vertices.map((v) => v.dy).reduce(min);
    double maxY = zone.vertices.map((v) => v.dy).reduce(max);

    // Check if zone touches image boundaries
    bool touchesLeftBoundary = minX <= 1;
    bool touchesRightBoundary = maxX >= semanticMap.width - 2;
    bool touchesTopBoundary = minY <= 1;
    bool touchesBottomBoundary = maxY >= semanticMap.height - 2;

    // Find actual surface edges (not image boundaries)
    List<EdgeInfo> detectedEdges = [];
    String dominantSurface = _getDominantSurface(zone, semanticMap);

    if (dominantSurface == PipelineClasses.footpath ||
        dominantSurface == PipelineClasses.road) {
      // Scan for left edge ONLY if left side doesn't touch boundary
      if (!touchesLeftBoundary) {
        EdgeInfo? leftEdge =
            _scanForVerticalEdge(zone, semanticMap, dominantSurface, true);
        if (leftEdge != null) detectedEdges.add(leftEdge);
      }

      // Scan for right edge ONLY if right side doesn't touch boundary
      if (!touchesRightBoundary) {
        EdgeInfo? rightEdge =
            _scanForVerticalEdge(zone, semanticMap, dominantSurface, false);
        if (rightEdge != null) detectedEdges.add(rightEdge);
      }
    }

    // Updated: Only consider zone as touching boundary if BOTH sides touch boundaries
    // This allows edge detection to work when only one side extends to boundary
    bool effectivelyBounded = touchesLeftBoundary && touchesRightBoundary;

    return EdgeAnalysisResult(
      detectedEdges: detectedEdges,
      touchesImageBoundary: effectivelyBounded, // Changed this logic
      dominantSurface: dominantSurface,
      centerPosition: _calculateZoneCenterPosition(zone),
    );
  }

  static EdgeInfo? _scanForVerticalEdge(
      TrapezoidZone zone,
      SemanticSegmentationMap semanticMap,
      String targetSurface,
      bool isLeftSide) {
    double minX = zone.vertices.map((v) => v.dx).reduce(min);
    double maxX = zone.vertices.map((v) => v.dx).reduce(max);
    double minY = zone.vertices.map((v) => v.dy).reduce(min);
    double maxY = zone.vertices.map((v) => v.dy).reduce(max);

    int scanX = isLeftSide ? minX.floor() + 2 : maxX.floor() - 2;
    int edgeTransitions = 0;
    double? edgePosition;

    // Scan vertically for surface transitions
    for (int y = minY.floor(); y < maxY.ceil(); y++) {
      if (y < 0 ||
          y >= semanticMap.height ||
          scanX < 0 ||
          scanX >= semanticMap.width) continue;

      String currentPixel = semanticMap.classMap[y][scanX];
      String adjacentPixel = '';

      if (isLeftSide && scanX > 0) {
        adjacentPixel = semanticMap.classMap[y][scanX - 1];
      } else if (!isLeftSide && scanX < semanticMap.width - 1) {
        adjacentPixel = semanticMap.classMap[y][scanX + 1];
      }

      // Check for transition from target surface to different surface
      if (currentPixel == targetSurface &&
          adjacentPixel != targetSurface &&
          adjacentPixel != PipelineClasses.unknown) {
        edgeTransitions++;
        edgePosition ??= scanX.toDouble();
      }
    }

    // Only consider it a valid edge if we see consistent transitions
    if (edgeTransitions >= 3) {
      return EdgeInfo(
        side: isLeftSide ? EdgeSide.left : EdgeSide.right,
        position: edgePosition!,
        surfaceType: targetSurface,
        isImageBoundary: false,
      );
    }

    return null;
  }

  static Offset _calculateZoneCenterPosition(TrapezoidZone zone) {
    double centerX = zone.vertices.map((v) => v.dx).reduce((a, b) => a + b) / 4;
    double centerY = zone.vertices.map((v) => v.dy).reduce((a, b) => a + b) / 4;
    return Offset(centerX, centerY);
  }

  static String _getDominantSurface(
      TrapezoidZone zone, SemanticSegmentationMap semanticMap) {
    Map<String, int> surfaceCounts = {};

    // Sample points within zone to determine dominant surface
    double minX = zone.vertices.map((v) => v.dx).reduce(min);
    double maxX = zone.vertices.map((v) => v.dx).reduce(max);
    double minY = zone.vertices.map((v) => v.dy).reduce(min);
    double maxY = zone.vertices.map((v) => v.dy).reduce(max);

    for (int r = minY.floor(); r < maxY.ceil(); r++) {
      for (int c = minX.floor(); c < maxX.ceil(); c++) {
        if (r >= 0 &&
            r < semanticMap.height &&
            c >= 0 &&
            c < semanticMap.width) {
          if (zone.contains(Offset(c.toDouble(), r.toDouble()))) {
            String surface = semanticMap.classMap[r][c];
            if (surface != PipelineClasses.unknown) {
              surfaceCounts[surface] = (surfaceCounts[surface] ?? 0) + 1;
            }
          }
        }
      }
    }

    String dominant = PipelineClasses.unknown;
    int maxCount = 0;
    surfaceCounts.forEach((surface, count) {
      if (count > maxCount) {
        maxCount = count;
        dominant = surface;
      }
    });

    return dominant;
  }
}

class EdgeAnalysisResult {
  final List<EdgeInfo> detectedEdges;
  final bool touchesImageBoundary;
  final String dominantSurface;
  final Offset centerPosition;

  EdgeAnalysisResult({
    required this.detectedEdges,
    required this.touchesImageBoundary,
    required this.dominantSurface,
    required this.centerPosition,
  });
}

class EdgeInfo {
  final EdgeSide side;
  final double position;
  final String surfaceType;
  final bool isImageBoundary;

  EdgeInfo({
    required this.side,
    required this.position,
    required this.surfaceType,
    required this.isImageBoundary,
  });
}

enum EdgeSide { left, right }
