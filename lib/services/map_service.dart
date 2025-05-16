import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapService {
  static final String _googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  /// Checks and listens to location updates
  static Future<void> getLocationUpdates({
    required Function(LatLng position) onLocationUpdate,
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      if (position.latitude != null && position.longitude != null) {
        onLocationUpdate(LatLng(position.latitude, position.longitude));
      }
    });
  }

  /// Fetches route polyline between two points
  static Future<List<LatLng>> getPolylinePoints({
    required LatLng origin,
    required LatLng destination,
  }) async {
    List<LatLng> polylineCoordinates = [];
    PolylinePoints polylinePoints = PolylinePoints();

    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      googleApiKey: _googleApiKey,
      request: PolylineRequest(
        origin: PointLatLng(origin.latitude, origin.longitude),
        destination: PointLatLng(destination.latitude, destination.longitude),
        mode: TravelMode.walking,
      ),
    );

    if (result.points.isNotEmpty) {
      polylineCoordinates =
          result.points.map((e) => LatLng(e.latitude, e.longitude)).toList();
    } else {
      debugPrint('MapService: No points found in polyline result');
    }

    return polylineCoordinates;
  }

  /// Generates a Polyline from a list of coordinates
  static Polyline generatePolylineFromPoints(List<LatLng> polylineCoordinates) {
    PolylineId id = const PolylineId('poly');
    return Polyline(
      polylineId: id,
      color: Colors.purple.shade700,
      width: 5,
      points: polylineCoordinates,
    );
  }

  /// Gets detailed navigation steps between two points
  static Future<List<NavigationStep>> getNavigationSteps({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=walking' // We're focusing on walking directions
        '&key=$_googleApiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          final routes = data['routes'] as List;

          if (routes.isNotEmpty) {
            final legs = routes[0]['legs'] as List;

            if (legs.isNotEmpty) {
              final steps = legs[0]['steps'] as List;

              List<NavigationStep> navigationSteps = [];

              for (final step in steps) {
                final String htmlInstructions = step['html_instructions'];
                // Clean HTML tags from instructions
                final instruction = htmlInstructions
                    .replaceAll(RegExp(r'<[^>]*>'), ' ')
                    .replaceAll('&nbsp;', ' ')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();

                final distance = step['distance']['text'];
                final distanceValue = step['distance']['value'] as int;
                final duration = step['duration']['text'];

                final startLocation = LatLng(
                  step['start_location']['lat'],
                  step['start_location']['lng'],
                );

                final endLocation = LatLng(
                  step['end_location']['lat'],
                  step['end_location']['lng'],
                );

                navigationSteps.add(
                  NavigationStep(
                    instruction: instruction,
                    distance: distance,
                    duration: duration,
                    startLocation: startLocation,
                    endLocation: endLocation,
                    distanceValue: distanceValue,
                  ),
                );
              }

              return navigationSteps;
            }
          }
        }

        return [];
      } else {
        debugPrint('Error getting navigation steps: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception getting navigation steps: $e');
      return [];
    }
  }

  /// Fetches place suggestions based on input query
  static Future<List<PlaceSuggestion>> getPlaceSuggestions(
      String input, LatLng? location) async {
    if (input.length < 2 || _googleApiKey.isEmpty) return [];

    try {
      // Use Nearby Search instead of Autocomplete for better results
      String url = 'https://maps.googleapis.com/maps/api/place/textsearch/json'
          '?query=${Uri.encodeComponent(input)}'
          '&key=$_googleApiKey';

      // Add location bias if available
      if (location != null) {
        url +=
            '&location=${location.latitude},${location.longitude}&radius=50000';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          final results = (data['results'] as List).take(3);

          List<PlaceSuggestion> suggestions = [];

          for (var result in results) {
            final placeId = result['place_id'];
            final name = result['name'];
            final address = result['formatted_address'] ?? '';

            // Calculate distance if we have user's location
            String distanceText = '';
            if (location != null) {
              final lat = result['geometry']['location']['lat'];
              final lng = result['geometry']['location']['lng'];

              final distanceInMeters = Geolocator.distanceBetween(
                location.latitude,
                location.longitude,
                lat,
                lng,
              );

              if (distanceInMeters < 1000) {
                distanceText = '${distanceInMeters.round()} m away';
              } else {
                distanceText =
                    '${(distanceInMeters / 1000).toStringAsFixed(1)} km away';
              }
            }

            suggestions.add(
              PlaceSuggestion(
                placeId: placeId,
                description:
                    '$name - $address${distanceText.isNotEmpty ? ' ($distanceText)' : ''}',
                distance: distanceText,
                distanceInMeters: location != null
                    ? Geolocator.distanceBetween(
                        location.latitude,
                        location.longitude,
                        result['geometry']['location']['lat'],
                        result['geometry']['location']['lng'],
                      )
                    : 0,
              ),
            );
          }

          return suggestions;
        }
      }

      return [];
    } catch (e) {
      debugPrint('Error getting place suggestions: $e');
      return [];
    }
  }

  /// Gets details for a selected place using its place_id
  // In getPlaceDetails method:
  static Future<LatLng?> getPlaceDetails(String placeId) async {
    if (_googleApiKey.isEmpty) {
      debugPrint('MapService: API key is empty!');
      return null;
    }

    try {
      debugPrint('MapService: Fetching details for place ID: $placeId');
      final url = 'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&fields=geometry'
          '&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      debugPrint(
          'MapService: Place Details response code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        debugPrint('MapService: Place Details status: ${data['status']}');

        if (data['status'] == 'OK') {
          final location = data['result']['geometry']['location'];
          final lat = location['lat'];
          final lng = location['lng'];
          debugPrint('MapService: Found location: $lat, $lng');
          return LatLng(lat, lng);
        } else {
          debugPrint('MapService: Place Details API error: ${data['status']}');
          if (data.containsKey('error_message')) {
            debugPrint('MapService: Error message: ${data['error_message']}');
          }
          return null;
        }
      } else {
        debugPrint('MapService: HTTP error: ${response.statusCode}');
        debugPrint('MapService: Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('MapService: Error getting place details: $e');
      return null;
    }
  }
}

class PlaceSuggestion {
  final String placeId;
  final String description;
  final String distance; // Formatted distance text
  final double distanceInMeters;

  PlaceSuggestion({
    required this.placeId,
    required this.description,
    this.distance = '',
    this.distanceInMeters = 0,
  });
}

class NavigationStep {
  final String instruction;
  final String distance;
  final String duration;
  final LatLng startLocation;
  final LatLng endLocation;
  final int distanceValue;

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startLocation,
    required this.endLocation,
    required this.distanceValue,
  });
}
