// lib/navigation_pipeline/pipeline_controller.dart
import 'dart:convert'; // For jsonEncode
import 'package:ultralytics_yolo/yolo_result.dart'; // Your YOLO result type

import 'pipeline_models.dart';
import 'pipeline_constants.dart';
import 'image_processor.dart';
import 'zone_definition.dart';
import 'zone_analyzer.dart';
import 'decision_engine.dart';
import 'calibration_service.dart'; // Ensure this is initialized

class NavigationPipelineController {
  List<TrapezoidZone> _zones = [];
  String _currentFocusZoneId =
      ZoneID.centerImmediate; // Start by focusing on center path

  NavigationPipelineController() {
    // Define the 6 zones once
    _zones =
        ZoneDefinition.divideIntoTrapezoidalRegions(MASK_WIDTH, MASK_HEIGHT);
    if (_zones.length != 6) {
      print(
          "PIPELINE_CONTROLLER_ERROR: Expected 6 zones, got ${_zones.length}");
      // Handle error appropriately
    }
    print("PIPELINE_CONTROLLER: Initialized with ${_zones.length} zones.");
  }

  Future<NavigationPipelineOutput> processFrame(
      List<YOLOResult> yoloResults) async {
    print(
        "PIPELINE_CONTROLLER: Processing new frame with ${yoloResults.length} YOLO results.");

    // Step 0: Preprocess YOLO results into a semantic map
    // Assuming yoloResults contains mask logits for each detected object
    SemanticSegmentationMap semanticMap = ImageProcessor.generateSemanticMap(
        yoloResults, MASK_WIDTH, MASK_HEIGHT);

    // Step 1 (already done in constructor): Trapezoidal Region Division (_zones)

    Map<String, ZoneAnalysisData> allZoneData = {};

    // Step 2-4, 7: Analyze each zone
    for (var zone in _zones) {
      ZoneAnalysisData zoneData =
          ZoneAnalyzer.analyzeZone(zone, semanticMap, yoloResults);
      DecisionEngine.calculateIntermediateScores(
          zoneData); // Calculate initial scores
      allZoneData[zone.id] = zoneData;
    }

    // Step 6: Future Zone Look-Ahead Analysis (influence immediate zone scores)
    // Apply future continuity from future zones to their corresponding immediate zones
    final immediateZoneIds = [
      ZoneID.leftImmediate,
      ZoneID.centerImmediate,
      ZoneID.rightImmediate
    ];
    for (String immediateId in immediateZoneIds) {
      String futureId =
          DecisionEngine.getCorrespondingFutureZoneId(immediateId);
      if (allZoneData.containsKey(immediateId) &&
          allZoneData.containsKey(futureId)) {
        DecisionEngine.applyFutureContinuity(
            allZoneData[immediateId]!, allZoneData[futureId]!);
      }
    }

    // Recalculate final scores for all zones after future continuity adjustment
    allZoneData.forEach((_, zoneData) {
      DecisionEngine.calculateFinalScore(zoneData);
    });

    // Step 5 & Enhanced Decision Matrix & Command Generation
    NavigationPipelineOutput output = DecisionEngine.generateNavigationCommands(
        allZoneData, _currentFocusZoneId);

    // Update focus for next frame (simple logic: aim for what was chosen)
    // _currentFocusZoneId = output.zoneAnalysis.currentBestZoneId; // This might be too jumpy.
    // A more stable approach might be to only shift focus if the command is harsh, or stick to center unless forced.
    // For now, let's keep it simple: if a turn is suggested, the focus shifts.
    if (output.navigationCommand.primaryAction.contains("left")) {
      _currentFocusZoneId = ZoneID.leftImmediate;
    } else if (output.navigationCommand.primaryAction.contains("right")) {
      _currentFocusZoneId = ZoneID.rightImmediate;
    } else {
      _currentFocusZoneId = ZoneID.centerImmediate;
    }

    print(
        "PIPELINE_CONTROLLER: Frame processing complete. Best immediate zone: ${output.zoneAnalysis.currentBestZoneId}");
    print(
        "PIPELINE_CONTROLLER: Generated command: ${output.navigationCommand.primaryAction} to ${output.navigationCommand.targetSurface}");
    // print("Full Output JSON: ${jsonEncode(output.toJson())}");
    return output;
  }
}
