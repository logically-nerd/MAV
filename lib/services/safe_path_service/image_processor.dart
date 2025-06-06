// lib/navigation_pipeline/image_processor.dart
import 'dart:math';
import 'package:ultralytics_yolo/yolo_result.dart'; // Assuming this is the correct import
import 'pipeline_models.dart';
import 'pipeline_constants.dart';

class ImageProcessor {
  static const int MIN_PATCH_SIZE = 25; // Minimum pixels for a valid patch
  static const double PATCH_FILL_THRESHOLD = 0.3; // 30% coverage needed

  // Processes YOLO results (logits masks) into a single semantic segmentation map.
  static SemanticSegmentationMap generateSemanticMap(
      List<YOLOResult> yoloResults, int mapWidth, int mapHeight) {
    print("IMAGE_PROCESSOR: Generating semantic map ($mapWidth x $mapHeight)");

    // Initialize map with 'unknown'
    List<List<String>> classMap = List.generate(
        mapHeight, (_) => List.filled(mapWidth, PipelineClasses.unknown));

    // First pass: Generate raw semantic map
    List<List<String>> rawClassMap = List.generate(
        mapHeight, (_) => List.filled(mapWidth, PipelineClasses.unknown));

    // For each pixel, determine the dominant class based on YOLO results
    for (int r = 0; r < mapHeight; r++) {
      for (int c = 0; c < mapWidth; c++) {
        String dominantClassAtPixel = PipelineClasses.unknown;
        double maxConfidenceAtPixel = -1.0;

        for (var result in yoloResults) {
          if (result.mask == null ||
              result.mask!.isEmpty ||
              result.mask![0].isEmpty) continue;
          // Ensure mask dimensions match, or handle potential coordinate mapping if they don't
          if (r >= result.mask!.length || c >= result.mask![0].length) continue;

          // The mask from YOLOResult is List<List<double>> (logits)
          double logit = result.mask![r][c];
          double probability = 1 / (1 + exp(-logit)); // Sigmoid

          String? pipelineClass =
              CLASS_NAME_MAPPING[result.className.toLowerCase()];
          if (pipelineClass == null)
            continue; // Skip if class not in our mapping

          // Check if pixel is within bounding box - useful optimization if masks are sparse
          // However, if masks are dense 160x160, this might not be strictly needed here
          // as we are iterating all pixels anyway.
          // Rect box = result.boundingBox; // These coords are for original image, not 160x160 mask space usually.
          // For now, we assume the 160x160 mask is directly usable.

          if (probability > MASK_PIXEL_CONFIDENCE_THRESHOLD) {
            // If multiple classes claim a pixel, one with higher probability (or model confidence) wins.
            // Here, we use the raw probability from the mask logit.
            // Could also incorporate result.confidence if mask values are not already scaled by it.
            double finalConfidence = probability * result.confidence;
            if (finalConfidence > maxConfidenceAtPixel) {
              maxConfidenceAtPixel = finalConfidence;
              dominantClassAtPixel = pipelineClass;
            }
          }
        }
        rawClassMap[r][c] = dominantClassAtPixel;
      }
    }
    // Second pass: Filter small patches
    classMap = _filterSmallPatches(rawClassMap, mapWidth, mapHeight);
    // NEW: Third pass - propagate static obstacles forward for future planning
    classMap = _propagateStaticObstacles(classMap, mapWidth, mapHeight);

    print("IMAGE_PROCESSOR: Semantic map generation complete.");
    return SemanticSegmentationMap(classMap, mapWidth, mapHeight);
  }

  // Filter out small isolated patches
  static List<List<String>> _filterSmallPatches(
      List<List<String>> rawMap, int width, int height) {
    List<List<String>> filteredMap =
        List.generate(height, (i) => List.from(rawMap[i]));

    List<List<bool>> visited =
        List.generate(height, (_) => List.filled(width, false));

    for (int r = 0; r < height; r++) {
      for (int c = 0; c < width; c++) {
        if (!visited[r][c]) {
          String currentClass = rawMap[r][c];
          List<Point> patch = [];

          // Flood fill to find connected component
          _floodFill(rawMap, visited, r, c, currentClass, patch, width, height);

          if (currentClass != PipelineClasses.unknown) {
            // If patch is too small, mark as unknown
            if (patch.length < MIN_PATCH_SIZE) {
              for (Point p in patch) {
                filteredMap[p.r][p.c] = PipelineClasses.unknown;
              }
            }
          } else {
            // NEW: Handle large unknown areas - treat as obstacles
            if (patch.length > MIN_PATCH_SIZE * 3) {
              // Large unknown area
              for (Point p in patch) {
                filteredMap[p.r][p.c] = PipelineClasses.nonWalkable;
              }
            }
          }
        }
      }
    }

    return filteredMap;
  }

  // NEW: Propagate static obstacles forward in the image
  static List<List<String>> _propagateStaticObstacles(
      List<List<String>> processedMap, int width, int height) {
    List<List<String>> propagatedMap =
        List.generate(height, (i) => List.from(processedMap[i]));

    const int PROPAGATION_DISTANCE = 20; // pixels forward

    for (int r = 0; r < height - PROPAGATION_DISTANCE; r++) {
      for (int c = 0; c < width; c++) {
        String currentClass = processedMap[r][c];

        // If current pixel is obstacle (people or non-walkable)
        if (currentClass == PipelineClasses.people ||
            currentClass == PipelineClasses.nonWalkable) {
          // Propagate obstacle influence forward (towards bottom of image)
          for (int futureR = r + 1;
              futureR < min(r + PROPAGATION_DISTANCE, height);
              futureR++) {
            // Only mark as obstacle if the future area is currently unknown
            if (propagatedMap[futureR][c] == PipelineClasses.unknown) {
              propagatedMap[futureR][c] = PipelineClasses.nonWalkable;
            }
          }
        }
      }
    }

    return propagatedMap;
  }

  static void _floodFill(
      List<List<String>> map,
      List<List<bool>> visited,
      int r,
      int c,
      String targetClass,
      List<Point> patch,
      int width,
      int height) {
    if (r < 0 ||
        r >= height ||
        c < 0 ||
        c >= width ||
        visited[r][c] ||
        map[r][c] != targetClass) {
      return;
    }

    visited[r][c] = true;
    patch.add(Point(r, c));

    // 8-connected flood fill
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr != 0 || dc != 0) {
          _floodFill(
              map, visited, r + dr, c + dc, targetClass, patch, width, height);
        }
      }
    }
  }
}

class Point {
  final int r, c;
  Point(this.r, this.c);
}
