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

  /// Fast place suggestions with 10km radius limit
  static Future<List<PlaceSuggestion>> getPlaceSuggestions(
      String input, LatLng? location) async {
    if (input.length < 2 || _googleApiKey.isEmpty) {
      debugPrint('MapService: Input too short or API key missing');
      return [];
    }

    try {
      debugPrint('MapService: Getting suggestions for "$input" near $location');

      List<PlaceSuggestion> allSuggestions = [];

      // Strategy 1: Quick Autocomplete API
      final autocompleteSuggestions =
          await _getAutocompleteSuggestions(input, location);
      allSuggestions.addAll(autocompleteSuggestions);
      debugPrint(
          'MapService: Got ${autocompleteSuggestions.length} autocomplete suggestions');

      // Strategy 2: Text Search API for backup
      if (allSuggestions.length < 3) {
        final textSuggestions = await _getTextSearchPlaces(input, location);

        for (final textSuggestion in textSuggestions) {
          bool exists = allSuggestions.any((existing) =>
              existing.placeId == textSuggestion.placeId ||
              existing.name.toLowerCase() == textSuggestion.name.toLowerCase());
          if (!exists) {
            allSuggestions.add(textSuggestion);
          }
        }
        debugPrint(
            'MapService: Total suggestions after text search: ${allSuggestions.length}');
      }

      // Return top 5 suggestions immediately
      final finalSuggestions = allSuggestions.take(5).toList();
      debugPrint(
          'MapService: Returning ${finalSuggestions.length} final suggestions');

      for (int i = 0; i < finalSuggestions.length; i++) {
        debugPrint(
            'MapService: Suggestion ${i + 1}: ${finalSuggestions[i].name}');
      }

      return finalSuggestions;
    } catch (e) {
      debugPrint('MapService: Error getting place suggestions: $e');
      return [];
    }
  }

  /// Quick autocomplete suggestions
  static Future<List<PlaceSuggestion>> _getAutocompleteSuggestions(
      String input, LatLng? location) async {
    try {
      String url =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(input)}'
          '&types=establishment|geocode';

      if (location != null) {
        url += '&location=${location.latitude},${location.longitude}'
            '&radius=${_maxSearchRadius.toInt()}';
      }

      url += '&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['predictions'] != null) {
          List<PlaceSuggestion> suggestions = [];

          for (var prediction in data['predictions']) {
            final placeId = prediction['place_id'];
            final description = prediction['description'] ?? '';
            final structuredFormatting =
                prediction['structured_formatting'] ?? {};
            final mainText = structuredFormatting['main_text'] ?? description;
            final secondaryText = structuredFormatting['secondary_text'] ?? '';

            String enhancedDescription = mainText;
            if (secondaryText.isNotEmpty) {
              enhancedDescription += ' - $secondaryText';
            }

            suggestions.add(PlaceSuggestion(
              placeId: placeId,
              description: enhancedDescription,
              distance: '',
              distanceInMeters: 0,
              name: mainText,
              address: secondaryText,
              types: (prediction['types'] as List<dynamic>?)?.join(', ') ?? '',
              rating: '',
              priceLevel: '',
            ));
          }

          return suggestions;
        }
      }

      return [];
    } catch (e) {
      debugPrint('MapService: Autocomplete exception: $e');
      return [];
    }
  }

  /// Text search for backup results
  static Future<List<PlaceSuggestion>> _getTextSearchPlaces(
      String input, LatLng? location) async {
    try {
      String url = 'https://maps.googleapis.com/maps/api/place/textsearch/json'
          '?query=${Uri.encodeComponent(input)}';

      if (location != null) {
        url += '&location=${location.latitude},${location.longitude}'
            '&radius=${_maxSearchRadius.toInt()}';
      }

      url += '&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['results'] != null) {
          return _parseSearchResults(data['results']);
        }
      }

      return [];
    } catch (e) {
      debugPrint('MapService: Text search exception: $e');
      return [];
    }
  }

  /// Parse search results
  static List<PlaceSuggestion> _parseSearchResults(List results) {
    List<PlaceSuggestion> suggestions = [];

    for (var result in results.take(5)) {
      final placeId = result['place_id'];
      final name = result['name'] ?? '';
      final address = result['vicinity'] ?? result['formatted_address'] ?? '';
      final rating = result['rating']?.toString() ?? '';

      String description = name;
      if (address.isNotEmpty) {
        description += ' - $address';
      }
      if (rating.isNotEmpty) {
        description += ' ⭐ $rating';
      }

      suggestions.add(PlaceSuggestion(
        placeId: placeId,
        description: description,
        distance: '',
        distanceInMeters: 0,
        name: name,
        address: address,
        types: (result['types'] as List<dynamic>?)?.join(', ') ?? '',
        rating: rating,
        priceLevel: '',
      ));
    }

    return suggestions;
  }

  /// Get place details with distance calculation
  static Future<PlaceSuggestion?> getPlaceDetailsWithDistance(
      String placeId, LatLng? userLocation) async {
    if (_googleApiKey.isEmpty) return null;

    try {
      final url = 'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&fields=geometry,name,vicinity,formatted_address,rating,types'
          '&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'];
          final location = result['geometry']['location'];
          final lat = location['lat'];
          final lng = location['lng'];
          final placeLocation = LatLng(lat, lng);

          String distanceText = '';
          double distanceInMeters = 0;

          if (userLocation != null) {
            distanceInMeters = calculateDistance(userLocation, placeLocation);
            distanceText = formatDistance(distanceInMeters);

            if (distanceInMeters > _maxSearchRadius) {
              return null; // Too far
            }
          }

          final name = result['name'] ?? '';
          final address =
              result['vicinity'] ?? result['formatted_address'] ?? '';
          final rating = result['rating']?.toString() ?? '';

          return PlaceSuggestion(
            placeId: placeId,
            description:
                '$name - $address${distanceText.isNotEmpty ? ' ($distanceText)' : ''}',
            distance: distanceText,
            distanceInMeters: distanceInMeters,
            name: name,
            address: address,
            types: (result['types'] as List<dynamic>?)?.join(', ') ?? '',
            rating: rating,
            priceLevel: '',
          );
        }
      }
    } catch (e) {
      debugPrint('MapService: Error getting place details: $e');
    }

    return null;
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
        .replaceAll('Proceed', 'Continue');

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
  static bool isApproachingTurn(LatLng current, LatLng waypoint,
      {double threshold = 100}) {
    final distance = calculateDistance(current, waypoint);
    return distance < threshold;
  }

  static bool hasReachedStepEnd(LatLng current, LatLng stepEnd,
      {double threshold = 15}) {
    final distance = calculateDistance(current, stepEnd);
    return distance < threshold;
  }

  static bool hasReachedDestination(LatLng current, LatLng destination,
      {double threshold = 20}) {
    final distance = calculateDistance(current, destination);
    return distance < threshold;
  }

  static double calculateTotalRemainingDistance(
    LatLng currentPosition,
    List<NavigationStep> steps,
    int currentStepIndex,
  ) {
    if (steps.isEmpty || currentStepIndex >= steps.length) return 0.0;

    double totalDistance = 0.0;

    final currentStep = steps[currentStepIndex];
    totalDistance +=
        calculateDistance(currentPosition, currentStep.endLocation);

    for (int i = currentStepIndex + 1; i < steps.length; i++) {
      totalDistance += steps[i].distanceValue.toDouble();
    }

    return totalDistance;
  }
}
