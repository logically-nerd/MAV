import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

class NavigationStep {
  final String instruction;
  final String distance;
  final String duration;
  final LatLng startLocation;
  final LatLng endLocation;
  final int distanceValue;
  final int durationValue;
  final double bearing;
  final int stepIndex;
  final String maneuver;

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startLocation,
    required this.endLocation,
    required this.distanceValue,
    required this.durationValue,
    required this.bearing,
    required this.stepIndex,
    required this.maneuver,
  });
}

class PlaceSuggestion {
  final String placeId;
  final String description;
  final String distance;
  final double distanceInMeters;
  final String name;
  final String address;
  final String types;
  final String rating;
  final String priceLevel;

  PlaceSuggestion({
    required this.placeId,
    required this.description,
    this.distance = '',
    this.distanceInMeters = 0,
    this.name = '',
    this.address = '',
    this.types = '',
    this.rating = '',
    this.priceLevel = '',
  });
}

class MapService {
  static final String _googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  static const double _maxSearchRadius = 10000; // 10km limit

  /// Enhanced location updates with better accuracy
  static Future<void> getLocationUpdates({
    required Function(LatLng position) onLocationUpdate,
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    // Enhanced location settings for better navigation
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2, // Update every 2 meters
      timeLimit: Duration(seconds: 5),
    );

    Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      onLocationUpdate(LatLng(position.latitude, position.longitude));
    });
  }

  /// Enhanced navigation steps with better instructions
  static Future<List<NavigationStep>> getNavigationSteps({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (_googleApiKey.isEmpty) {
      debugPrint('MapService: Google API key is missing');
      return [];
    }

    try {
      debugPrint(
          'MapService: Fetching enhanced directions from $origin to $destination');

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=walking'
        '&alternatives=false'
        '&language=en'
        '&units=metric'
        '&optimize=true'
        '&key=$_googleApiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final List<NavigationStep> steps = [];
          final route = data['routes'][0];
          final leg = route['legs'][0];

          debugPrint(
              'MapService: Route distance: ${leg['distance']['text']}, duration: ${leg['duration']['text']}');

          final rawSteps = leg['steps'] as List;

          for (int i = 0; i < rawSteps.length; i++) {
            final step = rawSteps[i];

            // Enhanced instruction processing
            String instruction =
                _processInstruction(step['html_instructions'].toString());

            // Add contextual information
            if (i == 0) {
              instruction = "Start by $instruction";
            } else if (i == rawSteps.length - 1) {
              instruction = "Finally, $instruction to reach your destination";
            }

            final startLocation = LatLng(
              step['start_location']['lat'],
              step['start_location']['lng'],
            );

            final endLocation = LatLng(
              step['end_location']['lat'],
              step['end_location']['lng'],
            );

            // Calculate bearing for this step
            final bearing = calculateBearing(startLocation, endLocation);

            steps.add(NavigationStep(
              instruction: instruction,
              distance: step['distance']['text'],
              duration: step['duration']['text'],
              startLocation: startLocation,
              endLocation: endLocation,
              distanceValue: step['distance']['value'],
              durationValue: step['duration']['value'],
              bearing: bearing,
              stepIndex: i,
              maneuver: step['maneuver'] ?? '',
            ));
          }

          debugPrint('MapService: Generated ${steps.length} navigation steps');
          return steps;
        } else {
          debugPrint(
              'MapService: No routes found or API error: ${data['status']}');
        }
      } else {
        debugPrint('MapService: HTTP error: ${response.statusCode}');
      }
      return [];
    } catch (e) {
      debugPrint('MapService: Error getting navigation steps: $e');
      return [];
    }
  }

  /// Gets location-prioritized place suggestions
  static Future<List<PlaceSuggestion>> getPlaceSuggestions(
      String input, LatLng? location) async {
    if (input.length < 2 || _googleApiKey.isEmpty) return [];

    try {
      List<PlaceSuggestion> allSuggestions = [];

      if (location != null) {
        // Strategy 1: Try Nearby Search first for better location accuracy
        final nearbySuggestions = await _getNearbyPlaces(input, location);
        allSuggestions.addAll(nearbySuggestions);

        // Strategy 2: Add Text Search with location bias
        final textSuggestions = await _getTextSearchPlaces(input, location);

        // Merge and deduplicate
        for (final textSuggestion in textSuggestions) {
          bool exists = allSuggestions
              .any((existing) => existing.placeId == textSuggestion.placeId);
          if (!exists) {
            allSuggestions.add(textSuggestion);
          }
        }
      } else {
        // No location - fallback to text search only
        allSuggestions = await _getTextSearchPlaces(input, null);
      }

      // Sort by distance if location is available
      if (location != null) {
        allSuggestions
            .sort((a, b) => a.distanceInMeters.compareTo(b.distanceInMeters));
      }

      // Return top 3 results for MAV
      final finalResults = allSuggestions.take(3).toList();

      // Log the results for debugging
      debugPrint('MapService: Found ${finalResults.length} place suggestions:');
      for (int i = 0; i < finalResults.length; i++) {
        debugPrint(
            '  ${i + 1}. ${finalResults[i].name} - ${finalResults[i].distance}');
      }

      return finalResults;
    } catch (e) {
      debugPrint('Error getting place suggestions: $e');
      return [];
    }
  }

  /// Get nearby places using Nearby Search API
  static Future<List<PlaceSuggestion>> _getNearbyPlaces(
      String query, LatLng location) async {
    try {
      // Try multiple searches with different radii and types
      List<PlaceSuggestion> suggestions = [];

      // Search 1: Small radius for very close places
      final closeResults = await _performNearbySearch(query, location, 2000);
      suggestions.addAll(closeResults);

      // Search 2: Medium radius if we don't have enough results
      if (suggestions.length < 5) {
        final mediumResults = await _performNearbySearch(query, location, 5000);
        for (final result in mediumResults) {
          bool exists =
              suggestions.any((existing) => existing.placeId == result.placeId);
          if (!exists) suggestions.add(result);
        }
      }

      return suggestions;
    } catch (e) {
      debugPrint('Error in nearby search: $e');
      return [];
    }
  }

  /// Check if approaching a turn (100m threshold)
  static bool isApproachingTurn(LatLng current, LatLng waypoint,
      {double threshold = 100}) {
    final distance = calculateDistance(current, waypoint);
    return distance < threshold;
  }

  /// Check if reached the end of a step (15m threshold)
  static bool hasReachedStepEnd(LatLng current, LatLng stepEnd,
      {double threshold = 15}) {
    final distance = calculateDistance(current, stepEnd);
    return distance < threshold;
  }

  /// Check if reached final destination (20m threshold)
  static bool hasReachedDestination(LatLng current, LatLng destination,
      {double threshold = 20}) {
    final distance = calculateDistance(current, destination);
    return distance < threshold;
  }

  /// Calculate total remaining distance through all steps
  static double calculateTotalRemainingDistance(
    LatLng currentPosition,
    List<NavigationStep> steps,
    int currentStepIndex,
  ) {
    if (steps.isEmpty || currentStepIndex >= steps.length) return 0.0;

    double totalDistance = 0.0;

    // Distance from current position to end of current step
    final currentStep = steps[currentStepIndex];
    totalDistance +=
        calculateDistance(currentPosition, currentStep.endLocation);

    // Add distances of all remaining steps
    for (int i = currentStepIndex + 1; i < steps.length; i++) {
      totalDistance += steps[i].distanceValue.toDouble();
    }

    return totalDistance;
  }

  /// Perform a single nearby search
  static Future<List<PlaceSuggestion>> _performNearbySearch(
      String query, LatLng location, int radius) async {
    final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${location.latitude},${location.longitude}'
        '&radius=$radius'
        '&keyword=${Uri.encodeComponent(query)}'
        '&key=$_googleApiKey';

    debugPrint('MapService: Nearby search URL: $url');

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        return _parseSearchResults(data['results'], location);
      } else {
        debugPrint('MapService: Nearby search status: ${data['status']}');
      }
    }

    return [];
  }

  /// Get places using Text Search with location bias
  static Future<List<PlaceSuggestion>> _getTextSearchPlaces(
      String input, LatLng? location) async {
    try {
      String url = 'https://maps.googleapis.com/maps/api/place/textsearch/json'
          '?query=${Uri.encodeComponent(input)}';

      // Add location bias for better proximity results
      if (location != null) {
        url += '&location=${location.latitude},${location.longitude}'
            '&radius=10000'; // 10km for text search
      }

      url += '&key=$_googleApiKey';

      debugPrint('MapService: Text search URL: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          return _parseSearchResults(data['results'], location);
        } else {
          debugPrint('MapService: Text search status: ${data['status']}');
          if (data['error_message'] != null) {
            debugPrint('MapService: Error message: ${data['error_message']}');
          }
        }
      }

      return [];
    } catch (e) {
      debugPrint('Error in text search: $e');
      return [];
    }
  }

  /// Parse search results into PlaceSuggestion objects
  static List<PlaceSuggestion> _parseSearchResults(
      List results, LatLng? location) {
    List<PlaceSuggestion> suggestions = [];

    for (var result in results) {
      final placeId = result['place_id'];
      final name = result['name'] ?? '';
      final address = result['vicinity'] ?? result['formatted_address'] ?? '';
      final types = (result['types'] as List<dynamic>?)?.join(', ') ?? '';
      final rating = result['rating']?.toString() ?? '';
      final priceLevel = result['price_level']?.toString() ?? '';

      String distanceText = '';
      double distanceInMeters = 0;

      if (location != null && result['geometry']?['location'] != null) {
        final lat = result['geometry']['location']['lat'];
        final lng = result['geometry']['location']['lng'];

        distanceInMeters = calculateDistance(
          location,
          LatLng(lat, lng),
        );

        distanceText = formatDistance(distanceInMeters);
      }

      // Create enhanced description
      String description = name;
      if (address.isNotEmpty) {
        description += ' - $address';
      }
      if (rating.isNotEmpty) {
        description += ' ⭐ $rating';
      }
      if (distanceText.isNotEmpty) {
        description += ' ($distanceText)';
      }

      suggestions.add(PlaceSuggestion(
        placeId: placeId,
        description: description,
        distance: distanceText,
        distanceInMeters: distanceInMeters,
        name: name,
        address: address,
        types: types,
        rating: rating,
        priceLevel: priceLevel,
      ));
    }

    return suggestions;
  }

  /// Get place coordinates only
  static Future<LatLng?> getPlaceDetails(String placeId) async {
    if (_googleApiKey.isEmpty) return null;

    try {
      final url = 'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&fields=geometry'
          '&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['result'] != null) {
          final location = data['result']['geometry']['location'];
          return LatLng(location['lat'], location['lng']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('MapService: Error getting place details: $e');
      return null;
    }
  }

  /// Enhanced polyline generation
  static Future<List<LatLng>> getPolylinePoints({
    required LatLng origin,
    required LatLng destination,
  }) async {
    List<LatLng> polylineCoordinates = [];
    PolylinePoints polylinePoints = PolylinePoints();

    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: _googleApiKey,
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.walking,
          optimizeWaypoints: true,
          avoidHighways: true,
        ),
      );

      if (result.points.isNotEmpty) {
        polylineCoordinates =
            result.points.map((e) => LatLng(e.latitude, e.longitude)).toList();
      }
    } catch (e) {
      debugPrint('MapService: Error generating polyline: $e');
    }

    return polylineCoordinates;
  }

  /// Generate polyline with enhanced styling
  static Polyline generatePolylineFromPoints(List<LatLng> polylineCoordinates) {
    return Polyline(
      polylineId: const PolylineId('walking_route'),
      color: Colors.blue,
      width: 6,
      points: polylineCoordinates,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );
  }

  // Helper methods
  static String _processInstruction(String htmlInstruction) {
    String instruction = htmlInstruction
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Make instructions more natural for TTS
    instruction = instruction
        .replaceAll('Head', 'Walk')
        .replaceAll('Continue', 'Keep walking')
        .replaceAll('Proceed', 'Continue')
        .replaceAll('Turn right', 'Turn right')
        .replaceAll('Turn left', 'Turn left')
        .replaceAll('Keep right', 'Stay to the right')
        .replaceAll('Keep left', 'Stay to the left')
        .replaceAll('Slight right', 'Turn slightly right')
        .replaceAll('Slight left', 'Turn slightly left')
        .replaceAll('Sharp right', 'Turn sharply right')
        .replaceAll('Sharp left', 'Turn sharply left');

    return instruction;
  }

  static double calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;

    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);

    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  static String getCardinalDirection(double bearing) {
    const directions = [
      'North',
      'Northeast',
      'East',
      'Southeast',
      'South',
      'Southwest',
      'West',
      'Northwest'
    ];
    final index = ((bearing + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  static double calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
        point1.latitude, point1.longitude, point2.latitude, point2.longitude);
  }

  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  static Future<LatLng?> getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  static bool isDestinationWithinRange(LatLng origin, LatLng destination) {
    final distance = calculateDistance(origin, destination);
    return distance <= _maxSearchRadius;
  }

  // Navigation helper methods
  static bool isApproachingWaypoint(
    LatLng current,
    LatLng waypoint, {
    double walkingThreshold = 50,
    double turningThreshold = 30,
    String? maneuver,
  }) {
    final distance = calculateDistance(current, waypoint);

    // Use different thresholds based on the type of maneuver
    if (maneuver != null &&
        (maneuver.contains('turn') ||
            maneuver.contains('right') ||
            maneuver.contains('left'))) {
      return distance < turningThreshold;
    }

    return distance < walkingThreshold;
  }

  static bool hasReachedWaypoint(LatLng current, LatLng waypoint,
      {double radius = 15}) {
    final distance = calculateDistance(current, waypoint);
    return distance < radius;
  }

  static bool isOffRoute(
      LatLng currentPosition, LatLng startPoint, LatLng endPoint,
      {double threshold = 25}) {
    final distanceToRoute =
        calculateDistanceToLineSegment(currentPosition, startPoint, endPoint);
    return distanceToRoute > threshold;
  }

  static double calculateDistanceToLineSegment(
      LatLng point, LatLng lineStart, LatLng lineEnd) {
    final A = point.latitude - lineStart.latitude;
    final B = point.longitude - lineStart.longitude;
    final C = lineEnd.latitude - lineStart.latitude;
    final D = lineEnd.longitude - lineStart.longitude;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;

    if (lenSq == 0) {
      return calculateDistance(point, lineStart);
    }

    final param = dot / lenSq;

    LatLng closestPoint;
    if (param < 0) {
      closestPoint = lineStart;
    } else if (param > 1) {
      closestPoint = lineEnd;
    } else {
      closestPoint = LatLng(
        lineStart.latitude + param * C,
        lineStart.longitude + param * D,
      );
    }

    return calculateDistance(point, closestPoint);
  }

  static double calculateRemainingDistance(
    LatLng currentPosition,
    List<NavigationStep> steps,
    int currentStepIndex,
  ) {
    if (steps.isEmpty || currentStepIndex >= steps.length) return 0.0;

    double totalDistance = 0.0;

    // Distance from current position to end of current step
    final currentStep = steps[currentStepIndex];
    totalDistance +=
        calculateDistance(currentPosition, currentStep.endLocation);

    // Add distances of all remaining steps
    for (int i = currentStepIndex + 1; i < steps.length; i++) {
      totalDistance += steps[i].distanceValue;
    }

    return totalDistance;
  }

  static String generateTTSInstruction(
    NavigationStep step, {
    double? distanceToStep,
    bool isApproaching = false,
    bool isImmediate = false,
  }) {
    String instruction = step.instruction;

    if (isApproaching && distanceToStep != null) {
      if (distanceToStep > 100) {
        instruction = "In ${(distanceToStep).round()} meters, $instruction";
      } else if (distanceToStep > 50) {
        instruction = "In about 50 meters, $instruction";
      } else {
        instruction = "Soon, $instruction";
      }
    } else if (isImmediate) {
      instruction = "Now, $instruction";
    }

    return instruction;
  }
}
