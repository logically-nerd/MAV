// import 'package:flutter_dotenv/flutter_dotenv.dart'; // For accessing .env variables
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:location/location.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';
// import 'dart:async';

// class MapService {
//   final Location _location = Location();
//   GoogleMapController? _mapController;
//   LocationData? _currentLocation;
//   final Set<Marker> _markers = {};
//   final StreamController<LocationData> _locationController =
//       StreamController<LocationData>.broadcast();
//   bool _isInitialized = false;

//   Stream<LocationData> get locationStream => _locationController.stream;

//   Future<void> initialize() async {
//     if (_isInitialized) return;

//     try {
//       bool serviceEnabled;
//       PermissionStatus permissionGranted;

//       serviceEnabled = await _location.serviceEnabled();
//       if (!serviceEnabled) {
//         serviceEnabled = await _location.requestService();
//         if (!serviceEnabled) {
//           throw Exception('Location services are disabled');
//         }
//       }

//       permissionGranted = await _location.hasPermission();
//       if (permissionGranted == PermissionStatus.denied) {
//         permissionGranted = await _location.requestPermission();
//         if (permissionGranted != PermissionStatus.granted) {
//           throw Exception('Location permissions are denied');
//         }
//       }

//       // Get initial location
//       _currentLocation = await _location.getLocation();
//       _locationController.add(_currentLocation!);

//       // Listen to location changes
//       _location.onLocationChanged.listen((LocationData currentLocation) {
//         _currentLocation = currentLocation;
//         _locationController.add(currentLocation);
//         updateMap();
//       });

//       _isInitialized = true;
//     } catch (e) {
//       print('Error initializing MapService: $e');
//       rethrow;
//     }
//   }

//   void setMapController(GoogleMapController controller) {
//     _mapController = controller;
//     if (_currentLocation != null) {
//       updateMap();
//     }
//   }

//   Future<void> updateMap() async {
//     if (_currentLocation == null || _mapController == null) return;

//     try {
//       final position = LatLng(
//         _currentLocation!.latitude!,
//         _currentLocation!.longitude!,
//       );

//       _markers.clear();
//       _markers.add(
//         Marker(
//           markerId: const MarkerId('current_location'),
//           position: position,
//           infoWindow: const InfoWindow(title: 'Current Location'),
//         ),
//       );

//       await _mapController!.animateCamera(
//         CameraUpdate.newCameraPosition(
//           CameraPosition(
//             target: position,
//             zoom: 15,
//           ),
//         ),
//       );
//     } catch (e) {
//       print('Error updating map: $e');
//     }
//   }

//   Future<List<Place>> searchNearbyPlaces(String query) async {
//     if (!_isInitialized) {
//       throw Exception('MapService not initialized');
//     }

//     if (_currentLocation == null) {
//       print('Current location is null');
//       return [];
//     }

//     final apiKey = dotenv.env['SECRET_KEY'] ?? ''; // Load the secret key from .env
//     final location =
//         '${_currentLocation!.latitude},${_currentLocation!.longitude}';
//     final radius = '5000'; // 5km radius

//     try {
//       print('Searching for: $query at location: $location');
//       final response = await http.get(
//         Uri.parse(
//           'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
//           'location=$location&radius=$radius&keyword=$query&key=$apiKey',
//         ),
//       );

//       print('Response status code: ${response.statusCode}');
//       print('Response body: ${response.body}');

//       if (response.statusCode == 200) {
//         final data = json.decode(response.body);
//         if (data['status'] == 'OK') {
//           final results = (data['results'] as List)
//               .map((place) => Place.fromJson(place))
//               .toList();
//           print('Found ${results.length} places');
//           return results;
//         } else {
//           print('API Error: ${data['status']}');
//           return [];
//         }
//       } else {
//         print('HTTP Error: ${response.statusCode}');
//         return [];
//       }
//     } catch (e) {
//       print('Error searching places: $e');
//       return [];
//     }
//   }

//   Set<Marker> get markers => _markers;

//   void addPlaceMarker(Place place) {
//     try {
//       _markers.add(
//         Marker(
//           markerId: MarkerId(place.name),
//           position: place.location,
//           infoWindow: InfoWindow(
//             title: place.name,
//             snippet: place.address,
//           ),
//         ),
//       );

//       if (_mapController != null) {
//         _mapController!.animateCamera(
//           CameraUpdate.newCameraPosition(
//             CameraPosition(
//               target: place.location,
//               zoom: 15,
//             ),
//           ),
//         );
//       }
//     } catch (e) {
//       print('Error adding place marker: $e');
//     }
//   }

//   void dispose() {
//     _locationController.close();
//     _mapController?.dispose();
//   }
// }

// class Place {
//   final String name;
//   final LatLng location;
//   final String? address;

//   Place({
//     required this.name,
//     required this.location,
//     this.address,
//   });

//   factory Place.fromJson(Map<String, dynamic> json) {
//     return Place(
//       name: json['name'],
//       location: LatLng(
//         json['geometry']['location']['lat'],
//         json['geometry']['location']['lng'],
//       ),
//       address: json['vicinity'],
//     );
//   }
// }

import 'package:flutter_dotenv/flutter_dotenv.dart'; // For accessing .env variables
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_polyline_points/flutter_polyline_points.dart'; // For decoding polyline points
import 'package:flutter/material.dart';

class MapService {
  // Location related members
  final Location _location = Location();
  LocationData? _currentLocation;
  final StreamController<LocationData> _locationController =
      StreamController<LocationData>.broadcast();
  bool _isInitialized = false;

  // Map related members
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  PolylinePoints polylinePoints = PolylinePoints();

  // Directions related members
  LatLng? _destination;
  bool _isNavigating = false;
  Timer? _navigationUpdateTimer;

  Stream<LocationData> get locationStream => _locationController.stream;
  Set<Marker> get markers => _markers;
  Set<Polyline> get polylines => _polylines;
  bool get isNavigating => _isNavigating;

  /// Initializes location services and starts listening for location updates
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Check and request location service enablement
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          throw Exception('Location services are disabled');
        }
      }

      // Check and request location permissions
      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          throw Exception('Location permissions are denied');
        }
      }

      // Get initial location
      _currentLocation = await _location.getLocation();
      _locationController.add(_currentLocation!);

      // Listen to location changes
      _location.onLocationChanged.listen((LocationData currentLocation) {
        _currentLocation = currentLocation;
        _locationController.add(currentLocation);

        // Update map only if we're not in navigation mode
        if (!_isNavigating) {
          updateCurrentLocationMarker();
        } else {
          // If navigating, we might want to update the route periodically
          // This is handled by the navigation timer
        }
      });

      _isInitialized = true;
    } catch (e) {
      print('Error initializing MapService: $e');
      rethrow;
    }
  }

  /// Sets the map controller and updates the map if we have current location
  void setMapController(GoogleMapController controller) {
    _mapController = controller;
    if (_currentLocation != null) {
      updateCurrentLocationMarker();
    }
  }

  /// Updates the map with current location marker
  Future<void> updateCurrentLocationMarker() async {
    if (_currentLocation == null || _mapController == null) return;

    try {
      final position = LatLng(
        _currentLocation!.latitude!,
        _currentLocation!.longitude!,
      );

      // Clear only the current location marker (preserve other markers)
      _markers
          .removeWhere((marker) => marker.markerId.value == 'current_location');

      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: position,
          infoWindow: const InfoWindow(title: 'Current Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );

      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: position,
            zoom: 15,
          ),
        ),
      );
    } catch (e) {
      print('Error updating current location marker: $e');
    }
  }

  /// Searches for nearby places using Google Places API
  Future<List<Place>> searchNearbyPlaces(String query) async {
    if (!_isInitialized) {
      throw Exception('MapService not initialized');
    }

    if (_currentLocation == null) {
      print('Current location is null');
      return [];
    }

    final apiKey = dotenv.env['SECRET_KEY'] ?? '';
    final location =
        '${_currentLocation!.latitude},${_currentLocation!.longitude}';
    final radius = '5000'; // 5km radius

    try {
      print('Searching for: $query at location: $location');
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
          'location=$location&radius=$radius&keyword=$query&key=$apiKey',
        ),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final results = (data['results'] as List)
              .map((place) => Place.fromJson(place))
              .toList();
          print('Found ${results.length} places');
          return results;
        } else {
          print('API Error: ${data['status']}');
          return [];
        }
      } else {
        print('HTTP Error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }

  /// Adds a marker for a place and optionally moves camera to it
  void addPlaceMarker(Place place, {bool moveCamera = true}) {
    try {
      _markers.add(
        Marker(
          markerId: MarkerId(place.placeId ?? place.name),
          position: place.location,
          infoWindow: InfoWindow(
            title: place.name,
            snippet: place.address,
          ),
        ),
      );

      if (moveCamera && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: place.location,
              zoom: 15,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error adding place marker: $e');
    }
  }

  /// Starts navigation to a destination
  Future<void> startNavigation(LatLng destination) async {
    if (_currentLocation == null) {
      throw Exception('Current location not available');
    }

    _destination = destination;
    _isNavigating = true;

    // Add destination marker
    _markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        infoWindow: const InfoWindow(title: 'Destination'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    // Get initial route
    await _updateRoute();

    // Set up periodic route updates (every 30 seconds)
    _navigationUpdateTimer =
        Timer.periodic(Duration(seconds: 30), (timer) async {
      if (_isNavigating) {
        await _updateRoute();
      }
    });
  }

  /// Stops the current navigation
  void stopNavigation() {
    _isNavigating = false;
    _destination = null;
    _navigationUpdateTimer?.cancel();
    _polylines.clear();

    // Remove destination marker
    _markers.removeWhere((marker) => marker.markerId.value == 'destination');

    // Update current location marker
    if (_currentLocation != null) {
      updateCurrentLocationMarker();
    }
  }

  /// Updates the route to destination
  Future<void> _updateRoute() async {
    if (_currentLocation == null || _destination == null) return;

    final apiKey = dotenv.env['SECRET_KEY'] ?? '';
    final origin =
        '${_currentLocation!.latitude},${_currentLocation!.longitude}';
    final destination = '${_destination!.latitude},${_destination!.longitude}';

    try {
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=$origin&destination=$destination&key=$apiKey',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          // Decode polyline points
          final points = data['routes'][0]['overview_polyline']['points'];
          final List<LatLng> polylineCoordinates = polylinePoints
              .decodePolyline(points)
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();

          // Clear existing polylines
          _polylines.clear();

          // Add new polyline
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: polylineCoordinates,
              color: Colors.blue,
              width: 5,
            ),
          );

          // Update camera to show both locations and route
          if (_mapController != null) {
            final bounds = _boundsFromLatLngList([
              LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
              _destination!,
            ]);

            await _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(bounds, 100),
            );
          }
        } else {
          print('Directions API Error: ${data['status']}');
        }
      } else {
        print('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating route: $e');
    }
  }

  /// Helper method to calculate bounds from a list of LatLng points
  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double? x0, x1, y0, y1;
    for (LatLng latLng in list) {
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
    }
    return LatLngBounds(
      northeast: LatLng(x1!, y1!),
      southwest: LatLng(x0!, y0!),
    );
  }

  /// Cleans up resources
  void dispose() {
    _locationController.close();
    _mapController?.dispose();
    _navigationUpdateTimer?.cancel();
  }
}

class Place {
  final String name;
  final LatLng location;
  final String? address;
  final String? placeId; // Added placeId for better marker identification

  Place({
    required this.name,
    required this.location,
    this.address,
    this.placeId,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      name: json['name'],
      location: LatLng(
        json['geometry']['location']['lat'],
        json['geometry']['location']['lng'],
      ),
      address: json['vicinity'],
      placeId: json['place_id'],
    );
  }
}
