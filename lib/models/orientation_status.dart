/// Model class representing the current orientation status of the phone
class OrientationStatus {
  /// Whether the phone is held vertically (perpendicular to ground)
  final bool isVertical;
  
  /// Whether the phone is held straight (not tilted left or right)
  final bool isStraight;
  
  /// X-axis tilt value from accelerometer (left/right tilt)
  final double xTilt;
  
  /// Y-axis tilt value from accelerometer (vertical orientation)
  final double yTilt;
  
  /// Z-axis tilt value from accelerometer (forward/backward tilt)
  final double zTilt;
  
  /// Constructor
  OrientationStatus({
    required this.isVertical,
    required this.isStraight,
    required this.xTilt,
    required this.yTilt,
    required this.zTilt,
  });
  
  /// Create a copy with updated values
  OrientationStatus copyWith({
    bool? isVertical,
    bool? isStraight,
    double? xTilt,
    double? yTilt,
    double? zTilt,
  }) {
    return OrientationStatus(
      isVertical: isVertical ?? this.isVertical,
      isStraight: isStraight ?? this.isStraight,
      xTilt: xTilt ?? this.xTilt,
      yTilt: yTilt ?? this.yTilt,
      zTilt: zTilt ?? this.zTilt,
    );
  }
  
  /// Creates a string representation of the orientation status
  @override
  String toString() {
    return 'OrientationStatus(vertical: $isVertical, straight: $isStraight, x: $xTilt, y: $yTilt, z: $zTilt)';
  }
  
  /// Returns true if the phone is in the correct position
  bool get isCorrectPosition => isVertical && isStraight;
  
  /// Returns a descriptive string about the current position
  String get positionDescription {
    if (isCorrectPosition) {
      return 'Correct position';
    } else if (!isVertical && !isStraight) {
      return 'Not vertical and not straight';
    } else if (!isVertical) {
      return 'Not vertical';
    } else {
      return 'Not straight';
    }
  }
}