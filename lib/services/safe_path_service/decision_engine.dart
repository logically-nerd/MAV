// lib/navigation_pipeline/decision_engine.dart
import 'dart:math';
import 'pipeline_models.dart';
import 'pipeline_constants.dart';
import 'calibration_service.dart';
import 'zone_analyzer.dart';

class DecisionEngine {
  // Calculates individual scores for a zone based on its analysis
  static void calculateIntermediateScores(ZoneAnalysisData zoneData) {
    // Surface Score
    zoneData.surfaceScore =
        (SURFACE_PRIORITY_SCORES[zoneData.dominantWalkableSurface] ??
                SURFACE_PRIORITY_SCORES[PipelineClasses.unknown])!
            .toDouble();
    
    // Penalize for large gaps
    if (zoneData.gapPercentage > GAP_LARGE_THRESHOLD_PERCENT) {
      zoneData.surfaceScore *= 0.5; // Heavy penalty
    } else if (zoneData.gapPercentage > GAP_SMALL_THRESHOLD_PERCENT) {
      zoneData.surfaceScore *= 0.8; // Small penalty
    }

    // People Clearance Score
    if (zoneData.peopleCount == 0) {
      zoneData.peopleClearanceScore =
          PEOPLE_CLEARANCE_SCORES["no_people"]!.toDouble();
    } else {
      // Use actual distance if available
      double distanceM = zoneData.closestPersonDistanceMetres;
      if (distanceM > 2.0) {
        zoneData.peopleClearanceScore = PEOPLE_CLEARANCE_SCORES["people_far"]!.toDouble();
      } else if (distanceM > 1.0) {
        zoneData.peopleClearanceScore = PEOPLE_CLEARANCE_SCORES["people_medium"]!.toDouble();
      } else {
        zoneData.peopleClearanceScore = PEOPLE_CLEARANCE_SCORES["people_close"]!.toDouble();
      }
      
      // Additional penalty for multiple people
      if (zoneData.peopleCount > 1) {
        zoneData.peopleClearanceScore *= 0.8;
      }
    }

    // Enhanced Edge Safety Score
    zoneData.edgeSafetyScore = _calculateEdgeSafetyScore(zoneData);
    
    // Future Continuity Score - set externally
    zoneData.futureContinuityScore = 50.0; // Neutral placeholder
  }

  static double _calculateEdgeSafetyScore(ZoneAnalysisData zoneData) {
    EdgeAnalysisResult edgeAnalysis = zoneData.edgeAnalysis;
    
    if (edgeAnalysis.touchesImageBoundary) {
      // Zone extends to image boundary - no edge margin concerns
      return 80.0; // Good score, no edge constraints
    }

    String surface = edgeAnalysis.dominantSurface;
    List<EdgeInfo> edges = edgeAnalysis.detectedEdges;
    
    if (edges.isEmpty) {
      return 70.0; // Neutral - no specific edges detected
    }

    if (surface == PipelineClasses.footpath) {
      // FOOTPATH: Maintain minimum distance from edges
      return _calculateFootpathEdgeScore(zoneData, edges);
      
    } else if (surface == PipelineClasses.road) {
      // ROAD: Stay maximum distance from nearest edge
      return _calculateRoadEdgeScore(zoneData, edges);
    }

    return 70.0; // Default neutral score
  }

  static double _calculateFootpathEdgeScore(ZoneAnalysisData zoneData, List<EdgeInfo> edges) {
    EdgeAnalysisResult edgeAnalysis = zoneData.edgeAnalysis;
    double centerX = edgeAnalysis.centerPosition.dx;
    
    double minDistanceFromAnyEdge = double.infinity;
    
    for (EdgeInfo edge in edges) {
      double distancePixels = (centerX - edge.position).abs();
      double distanceMeters = CalibrationService.pixelsToMeters(distancePixels);
      minDistanceFromAnyEdge = min(minDistanceFromAnyEdge, distanceMeters);
    }

    if (minDistanceFromAnyEdge == double.infinity) {
      return 80.0; // No edges detected
    }

    // Score based on minimum required distance
    if (minDistanceFromAnyEdge >= ZoneAnalyzer.MIN_EDGE_DISTANCE_FOOTPATH) {
      return 100.0; // Perfect - sufficient margin from all edges
    } else if (minDistanceFromAnyEdge >= ZoneAnalyzer.MIN_EDGE_DISTANCE_FOOTPATH * 0.7) {
      return 70.0; // Acceptable but not ideal
    } else if (minDistanceFromAnyEdge >= ZoneAnalyzer.MIN_EDGE_DISTANCE_FOOTPATH * 0.5) {
      return 40.0; // Poor - too close to edge
    } else {
      return 10.0; // Dangerous - very close to edge
    }
  }

  static double _calculateRoadEdgeScore(ZoneAnalysisData zoneData, List<EdgeInfo> edges) {
    EdgeAnalysisResult edgeAnalysis = zoneData.edgeAnalysis;
    double centerX = edgeAnalysis.centerPosition.dx;
    
    double minDistanceFromAnyEdge = double.infinity;
    
    for (EdgeInfo edge in edges) {
      double distancePixels = (centerX - edge.position).abs();
      double distanceMeters = CalibrationService.pixelsToMeters(distancePixels);
      minDistanceFromAnyEdge = min(minDistanceFromAnyEdge, distanceMeters);
    }

    if (minDistanceFromAnyEdge == double.infinity) {
      return 60.0; // No edges detected - neutral for road
    }

    // For roads: being closer to edge is generally better (safer shoulder)
    if (minDistanceFromAnyEdge <= 0.5) {
      return 100.0; // Excellent - close to road edge/shoulder
    } else if (minDistanceFromAnyEdge <= 1.0) {
      return 85.0; // Good - reasonably close to edge
    } else if (minDistanceFromAnyEdge <= ZoneAnalyzer.MAX_DISTANCE_FROM_ROAD_EDGE) {
      return 70.0; // Acceptable
    } else {
      return 30.0; // Poor - too far from road edge (middle of road)
    }
  }

  static void calculateFinalScore(ZoneAnalysisData zoneData) {
    zoneData.finalScore = (zoneData.surfaceScore * SURFACE_SCORE_WEIGHT) +
        (zoneData.peopleClearanceScore * PEOPLE_CLEARANCE_WEIGHT) +
        (zoneData.edgeSafetyScore * EDGE_SAFETY_WEIGHT) +
        (zoneData.futureContinuityScore * FUTURE_CONTINUITY_WEIGHT);
    print(
        "DECISION_ENGINE: Zone ${zoneData.zoneId} - Surface: ${zoneData.surfaceScore}, People: ${zoneData.peopleClearanceScore}, Edge: ${zoneData.edgeSafetyScore}, Future: ${zoneData.futureContinuityScore} => FINAL: ${zoneData.finalScore}");
  }

  // Update immediate zone scores based on future zone analysis
  static void applyFutureContinuity(ZoneAnalysisData immediateZone,
      ZoneAnalysisData correspondingFutureZone) {
    print(
        "DECISION_ENGINE: Applying future continuity from ${correspondingFutureZone.zoneId} to ${immediateZone.zoneId}");
    
    if (immediateZone.dominantWalkableSurface == PipelineClasses.footpath &&
        correspondingFutureZone.dominantWalkableSurface == PipelineClasses.footpath &&
        (correspondingFutureZone.classCoveragePercentage[PipelineClasses.footpath] ?? 0.0) > 0.5) {
      immediateZone.futureContinuityScore = 100.0; // Strong positive signal
    } else if (immediateZone.dominantWalkableSurface != PipelineClasses.unknown &&
        correspondingFutureZone.dominantWalkableSurface != PipelineClasses.unknown &&
        immediateZone.dominantWalkableSurface != correspondingFutureZone.dominantWalkableSurface) {
      immediateZone.futureContinuityScore = 30.0; // Surface change, less preferred
    } else if (correspondingFutureZone.dominantWalkableSurface == PipelineClasses.unknown ||
        (correspondingFutureZone.classCoveragePercentage[correspondingFutureZone.dominantWalkableSurface] ?? 0.0) < 0.2) {
      immediateZone.futureContinuityScore = 10.0; // Path likely ends or becomes unclear
    } else {
      immediateZone.futureContinuityScore = 60.0; // Default moderate continuity
    }
  }

  static NavigationPipelineOutput generateNavigationCommands(
      Map<String, ZoneAnalysisData> allZoneData, String currentFocusZoneId) {
    
    // Step 1: Calculate final scores for all zones
    allZoneData.forEach((_, zoneData) {
      calculateFinalScore(zoneData);
    });

    // Step 2: Center preference logic
    List<String> immediateZoneIds = [
      ZoneID.leftImmediate, ZoneID.centerImmediate, ZoneID.rightImmediate
    ];

    ZoneAnalysisData? centerZone = allZoneData[ZoneID.centerImmediate];
    ZoneAnalysisData? bestZone = centerZone;
    double bestScore = centerZone?.finalScore ?? 0.0;

    // Only switch from center if there's a SIGNIFICANT advantage
    const double SIGNIFICANT_ADVANTAGE_THRESHOLD = 25.0;

    for (String zoneId in immediateZoneIds) {
      ZoneAnalysisData? zone = allZoneData[zoneId];
      if (zone != null && zone.zoneId != ZoneID.centerImmediate) {
        // Require significant advantage to move away from center
        if (zone.finalScore > bestScore + SIGNIFICANT_ADVANTAGE_THRESHOLD) {
          bestScore = zone.finalScore;
          bestZone = zone;
        }
      }
    }

    // If center zone is still competitive, prefer it
    if (centerZone != null && bestZone != null && 
        centerZone.finalScore >= bestZone.finalScore - 10.0) {
      bestZone = centerZone;
    }

    if (bestZone == null) {
      return _createFallbackOutput();
    }

    // Step 3: Generate commands with edge awareness
    NavigationCommand navCommand = _generateEdgeAwareCommand(bestZone, allZoneData);
    
    // Create zone analysis output
    Map<String, double> allScores = {};
    allZoneData.forEach((key, value) {
      allScores[key] = value.finalScore;
    });
    
    ZoneAnalysisOutput zoneOutput = ZoneAnalysisOutput(
      currentBestZoneId: bestZone.zoneId,
      scores: allScores,
    );

    // Safety Context
    int totalPeople = 0;
    allZoneData.values
        .where((z) => immediateZoneIds.contains(z.zoneId))
        .forEach((z) {
      totalPeople += z.peopleCount;
    });

    PeopleDetected peopleCtx = PeopleDetected(
      count: totalPeople,
      closestDistance: bestZone.closestPersonDistanceMetres,
      clearanceAvailable: bestZone.arePeopleMarginsClear,
    );
    
    EdgeDetectionContext edgeCtx = EdgeDetectionContext(
      footpathEdges: bestZone.edgeAnalysis.detectedEdges
          .where((e) => e.surfaceType == PipelineClasses.footpath)
          .map((e) => "${e.side.name}_detected")
          .toList(),
      marginsAdequate: bestZone.edgeAnalysis.detectedEdges.isNotEmpty,
      minimumDistanceMaintained: _calculateMinEdgeDistance(bestZone),
    );
    
    SurfaceQuality surfaceCtx = SurfaceQuality(
      current: allZoneData[currentFocusZoneId]?.dominantWalkableSurface ?? PipelineClasses.unknown,
      target: navCommand.targetSurface,
      continuity: "good", // Simplified
    );
    
    SafetyContext safetyCtx = SafetyContext(
        peopleDetected: peopleCtx,
        edgeDetection: edgeCtx,
        surfaceQuality: surfaceCtx);

    // Future Guidance
    String lookAhead = "path_continues";
    ZoneAnalysisData? correspondingFutureZone = allZoneData[getCorrespondingFutureZoneId(bestZone.zoneId)];
    if (correspondingFutureZone != null) {
      lookAhead = "${correspondingFutureZone.dominantWalkableSurface}_ahead";
    }

    FutureGuidance futureGuid = FutureGuidance(
      lookAhead: lookAhead,
      upcomingChanges: "none",
      recommendedPreparation: "continue_current_path",
    );

    // Accessibility
    String voiceCmd = "${navCommand.primaryAction.replaceAll('_', ' ')} for ${navCommand.targetSurface}";
    if (navCommand.reason != "optimal_center_path") {
      voiceCmd += " - ${navCommand.reason.replaceAll('_', ' ')}";
    }

    AccessibilityOutput accessibilityOut = AccessibilityOutput(
      voiceCommand: voiceCmd,
      hapticPattern: "${navCommand.primaryAction}_vibration",
      audioCue: "${navCommand.targetSurface}_sound",
    );

    return NavigationPipelineOutput(
      navigationCommand: navCommand,
      zoneAnalysis: zoneOutput,
      safetyContext: safetyCtx,
      futureGuidance: futureGuid,
      accessibility: accessibilityOut,
    );
  }

  static double _calculateMinEdgeDistance(ZoneAnalysisData zoneData) {
    EdgeAnalysisResult edgeAnalysis = zoneData.edgeAnalysis;
    double centerX = edgeAnalysis.centerPosition.dx;
    
    double minDistance = double.infinity;
    for (EdgeInfo edge in edgeAnalysis.detectedEdges) {
      double distance = (centerX - edge.position).abs();
      double distanceMeters = CalibrationService.pixelsToMeters(distance);
      minDistance = min(minDistance, distanceMeters);
    }
    
    return minDistance == double.infinity ? 0.0 : minDistance;
  }

  static NavigationCommand _generateEdgeAwareCommand(
      ZoneAnalysisData bestZone, Map<String, ZoneAnalysisData> allZoneData) {
    
    String primaryAction = NavigationAction.continueCenter;
    String reason = "center_preferred";
    double angleAdjustment = 0.0;

    if (bestZone.zoneId == ZoneID.centerImmediate) {
      // Check if center zone needs edge adjustment
      EdgeAnalysisResult edgeAnalysis = bestZone.edgeAnalysis;
      
      if (!edgeAnalysis.touchesImageBoundary && edgeAnalysis.detectedEdges.isNotEmpty) {
        NavigationCommand? adjustment = _getEdgeAdjustmentCommand(bestZone);
        if (adjustment != null) {
          return adjustment;
        }
      }
      
      primaryAction = NavigationAction.continueCenter;
      reason = "optimal_center_path";
      
    } else if (bestZone.zoneId == ZoneID.leftImmediate) {
      ZoneAnalysisData? centerZone = allZoneData[ZoneID.centerImmediate];
      double scoreDiff = bestZone.finalScore - (centerZone?.finalScore ?? 0.0);
      
      if (scoreDiff > 30.0) {
        primaryAction = NavigationAction.harshLeft;
        angleAdjustment = ANGLE_HARSH;
        reason = "significant_advantage_left";
      } else {
        primaryAction = NavigationAction.slightLeft;
        angleAdjustment = ANGLE_SLIGHT;
        reason = "better_path_left";
      }
      
    } else if (bestZone.zoneId == ZoneID.rightImmediate) {
      ZoneAnalysisData? centerZone = allZoneData[ZoneID.centerImmediate];
      double scoreDiff = bestZone.finalScore - (centerZone?.finalScore ?? 0.0);
      
      if (scoreDiff > 30.0) {
        primaryAction = NavigationAction.harshRight;
        angleAdjustment = ANGLE_HARSH;
        reason = "significant_advantage_right";
      } else {
        primaryAction = NavigationAction.slightRight;
        angleAdjustment = ANGLE_SLIGHT;
        reason = "better_path_right";
      }
    }

    return NavigationCommand(
      primaryAction: primaryAction,
      targetSurface: bestZone.dominantWalkableSurface,
      confidence: bestZone.finalScore / 100.0,
      angleAdjustment: angleAdjustment,
      reason: reason,
    );
  }

  static NavigationCommand? _getEdgeAdjustmentCommand(ZoneAnalysisData zoneData) {
    EdgeAnalysisResult edgeAnalysis = zoneData.edgeAnalysis;
    String surface = edgeAnalysis.dominantSurface;
    
    if (surface == PipelineClasses.footpath) {
      return _getFootpathEdgeAdjustment(zoneData);
    } else if (surface == PipelineClasses.road) {
      return _getRoadEdgeAdjustment(zoneData);
    }
    
    return null;
  }

  static NavigationCommand? _getFootpathEdgeAdjustment(ZoneAnalysisData zoneData) {
    EdgeAnalysisResult edgeAnalysis = zoneData.edgeAnalysis;
    double centerX = edgeAnalysis.centerPosition.dx;
    
    EdgeInfo? closestEdge;
    double minDistance = double.infinity;
    
    for (EdgeInfo edge in edgeAnalysis.detectedEdges) {
      double distance = (centerX - edge.position).abs();
      if (distance < minDistance) {
        minDistance = distance;
        closestEdge = edge;
      }
    }
    
    if (closestEdge == null) return null;
    
    double distanceMeters = CalibrationService.pixelsToMeters(minDistance);
    
    if (distanceMeters < ZoneAnalyzer.MIN_EDGE_DISTANCE_FOOTPATH) {
      // Too close to edge - move away
      if (closestEdge.side == EdgeSide.left) {
        return NavigationCommand(
          primaryAction: NavigationAction.slightRight,
          targetSurface: PipelineClasses.footpath,
          confidence: 0.8,
          angleAdjustment: ANGLE_SLIGHT,
          reason: "maintaining_footpath_margin_from_left_edge",
        );
      } else {
        return NavigationCommand(
          primaryAction: NavigationAction.slightLeft,
          targetSurface: PipelineClasses.footpath,
          confidence: 0.8,
          angleAdjustment: ANGLE_SLIGHT,
          reason: "maintaining_footpath_margin_from_right_edge",
        );
      }
    }
    
    return null;
  }

  static NavigationCommand? _getRoadEdgeAdjustment(ZoneAnalysisData zoneData) {
    EdgeAnalysisResult edgeAnalysis = zoneData.edgeAnalysis;
    double centerX = edgeAnalysis.centerPosition.dx;
    
    EdgeInfo? closestEdge;
    double minDistance = double.infinity;
    
    for (EdgeInfo edge in edgeAnalysis.detectedEdges) {
      double distance = (centerX - edge.position).abs();
      if (distance < minDistance) {
        minDistance = distance;
        closestEdge = edge;
      }
    }
    
    if (closestEdge == null) return null;
    
    double distanceMeters = CalibrationService.pixelsToMeters(minDistance);
    
    if (distanceMeters > ZoneAnalyzer.MAX_DISTANCE_FROM_ROAD_EDGE) {
      // Too far from edge - move closer to safer side
      if (closestEdge.side == EdgeSide.left) {
        return NavigationCommand(
          primaryAction: NavigationAction.slightLeft,
          targetSurface: PipelineClasses.road,
          confidence: 0.8,
          angleAdjustment: ANGLE_SLIGHT,
          reason: "moving_closer_to_road_edge_for_safety",
        );
      } else {
        return NavigationCommand(
          primaryAction: NavigationAction.slightRight,
          targetSurface: PipelineClasses.road,
          confidence: 0.8,
          angleAdjustment: ANGLE_SLIGHT,
          reason: "moving_closer_to_road_edge_for_safety",
        );
      }
    }
    
    return null;
  }

  static String getCorrespondingFutureZoneId(String immediateZoneId) {
    if (immediateZoneId == ZoneID.leftImmediate) return ZoneID.leftFuture;
    if (immediateZoneId == ZoneID.centerImmediate) return ZoneID.centerFuture;
    if (immediateZoneId == ZoneID.rightImmediate) return ZoneID.rightFuture;
    return "";
  }

  static String getCorrespondingImmediateZoneId(String futureZoneId) {
    if (futureZoneId == ZoneID.leftFuture) return ZoneID.leftImmediate;
    if (futureZoneId == ZoneID.centerFuture) return ZoneID.centerImmediate;
    if (futureZoneId == ZoneID.rightFuture) return ZoneID.rightImmediate;
    return "";
  }

  static NavigationPipelineOutput _createFallbackOutput() {
    // Creates a default "stop" or "caution" output
    NavigationCommand navCmd = NavigationCommand(
        primaryAction: NavigationAction.stopWait,
        targetSurface: PipelineClasses.unknown,
        confidence: 0.1,
        angleAdjustment: 0,
        reason: "no_safe_path_found");
    
    return NavigationPipelineOutput(
        navigationCommand: navCmd,
        zoneAnalysis: ZoneAnalysisOutput(currentBestZoneId: "none", scores: {}),
        safetyContext: SafetyContext(
            peopleDetected: PeopleDetected(
                count: 0,
                closestDistance: double.infinity,
                clearanceAvailable: false),
            edgeDetection: EdgeDetectionContext(
                footpathEdges: [],
                marginsAdequate: false,
                minimumDistanceMaintained: 0),
            surfaceQuality: SurfaceQuality(
                current: PipelineClasses.unknown,
                target: PipelineClasses.unknown,
                continuity: "unknown")),
        futureGuidance: FutureGuidance(
            lookAhead: "unknown_path",
            upcomingChanges: "caution_needed",
            recommendedPreparation: "proceed_with_caution"),
        accessibility: AccessibilityOutput(
            voiceCommand: "Caution: Path unclear. Please wait.",
            hapticPattern: "stop_vibration",
            audioCue: "warning_sound"));
  }
}
