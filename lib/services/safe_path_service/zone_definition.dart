// lib/navigation_pipeline/zone_definition.dart
import 'dart:ui'; // For Offset
import 'pipeline_models.dart';
import 'pipeline_constants.dart';

class ZoneDefinition {
  static List<TrapezoidZone> divideIntoTrapezoidalRegions(
      int MASK_WIDTH, int MASK_HEIGHT) {
    print(
        "ZONE_DEFINITION: Dividing into 6 trapezoidal regions (30% immediate + 20% next).");
    List<TrapezoidZone> zones = [];

    // Updated zone percentages
    double immediateZoneHeightRatio = 0.40; // Bottom 30% = immediate
    double nextZoneHeightRatio = 0.30; // Next 20% = next step

    double immediateTopY = MASK_HEIGHT * (1.0 - immediateZoneHeightRatio);
    double nextTopY =
        MASK_HEIGHT * (1.0 - immediateZoneHeightRatio - nextZoneHeightRatio);

    // CORRECTED: More aggressive perspective narrowing
    double centerBottomWidth = MASK_WIDTH * 0.50; // Wider at bottom
    double centerImmediateTopWidth =
        MASK_WIDTH * 0.30; // Medium at immediate top
    double centerNextTopWidth = MASK_WIDTH * 0.20; // Much narrower at next top

    // Calculate center positions
    double centerBottomStartX = (MASK_WIDTH - centerBottomWidth) / 2;
    double centerBottomEndX = centerBottomStartX + centerBottomWidth;

    double centerImmediateTopStartX =
        (MASK_WIDTH - centerImmediateTopWidth) / 2;
    double centerImmediateTopEndX =
        centerImmediateTopStartX + centerImmediateTopWidth;

    double centerNextTopStartX = (MASK_WIDTH - centerNextTopWidth) / 2;
    double centerNextTopEndX = centerNextTopStartX + centerNextTopWidth;

    // IMMEDIATE ZONES (Bottom 30%) - TRUE TRAPEZOIDS
    zones.add(TrapezoidZone(
      id: ZoneID.centerImmediate,
      vertices: [
        Offset(centerImmediateTopStartX, immediateTopY), // Top-left (narrower)
        Offset(centerImmediateTopEndX, immediateTopY), // Top-right (narrower)
        Offset(centerBottomEndX, MASK_HEIGHT - 1.0), // Bottom-right (wider)
        Offset(centerBottomStartX, MASK_HEIGHT - 1.0), // Bottom-left (wider)
      ],
    ));

    zones.add(TrapezoidZone(
      id: ZoneID.leftImmediate,
      vertices: [
        Offset(0, immediateTopY), // Top-left (image edge)
        Offset(centerImmediateTopStartX,
            immediateTopY), // Top-right (narrow center)
        Offset(centerBottomStartX,
            MASK_HEIGHT - 1.0), // Bottom-right (wide center)
        Offset(0, MASK_HEIGHT - 1.0), // Bottom-left (image edge)
      ],
    ));

    zones.add(TrapezoidZone(
      id: ZoneID.rightImmediate,
      vertices: [
        Offset(
            centerImmediateTopEndX, immediateTopY), // Top-left (narrow center)
        Offset(MASK_WIDTH - 1.0, immediateTopY), // Top-right (image edge)
        Offset(
            MASK_WIDTH - 1.0, MASK_HEIGHT - 1.0), // Bottom-right (image edge)
        Offset(
            centerBottomEndX, MASK_HEIGHT - 1.0), // Bottom-left (wide center)
      ],
    ));

    // NEXT ZONES (20% above immediate) - CONTINUING PERSPECTIVE
    zones.add(TrapezoidZone(
      id: ZoneID.centerFuture,
      vertices: [
        Offset(centerNextTopStartX, nextTopY), // Top-left (very narrow)
        Offset(centerNextTopEndX, nextTopY), // Top-right (very narrow)
        Offset(centerImmediateTopEndX, immediateTopY), // Bottom-right (medium)
        Offset(centerImmediateTopStartX, immediateTopY), // Bottom-left (medium)
      ],
    ));

    zones.add(TrapezoidZone(
      id: ZoneID.leftFuture,
      vertices: [
        Offset(0, nextTopY), // Top-left (image edge)
        Offset(centerNextTopStartX, nextTopY), // Top-right (very narrow)
        Offset(
            centerImmediateTopStartX, immediateTopY), // Bottom-right (medium)
        Offset(0, immediateTopY), // Bottom-left (image edge)
      ],
    ));

    zones.add(TrapezoidZone(
      id: ZoneID.rightFuture,
      vertices: [
        Offset(centerNextTopEndX, nextTopY), // Top-left (very narrow)
        Offset(MASK_WIDTH - 1.0, nextTopY), // Top-right (image edge)
        Offset(MASK_WIDTH - 1.0, immediateTopY), // Bottom-right (image edge)
        Offset(centerImmediateTopEndX, immediateTopY), // Bottom-left (medium)
      ],
    ));

    // Debug output
    print("ZONE_DEFINITION: Perspective layout:");
    print(
        "  Bottom width: ${centerBottomWidth} (${(centerBottomWidth / MASK_WIDTH * 100).toStringAsFixed(1)}%)");
    print(
        "  Immediate top width: ${centerImmediateTopWidth} (${(centerImmediateTopWidth / MASK_WIDTH * 100).toStringAsFixed(1)}%)");
    print(
        "  Next top width: ${centerNextTopWidth} (${(centerNextTopWidth / MASK_WIDTH * 100).toStringAsFixed(1)}%)");

    return zones;
  }
}
