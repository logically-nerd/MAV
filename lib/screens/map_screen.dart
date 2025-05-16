import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/map_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  Map<PolylineId, Polyline> polylines = {};
  Set<Marker> _markers = {};

  LatLng? _currentPosition, _destinationPosition;
  bool _isLoading = true;

  List<PlaceSuggestion> _suggestions = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _isNavigating = false;
  List<NavigationStep> _navigationSteps = [];
  String _currentInstructionText = '';
  int _currentStepIndex = 0;
  Timer? _navigationTimer;
  double _distanceToDestination = 0.0; // in meters
  bool _hasAnnouncedNextTurn = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _navigationTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Request permission first
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permission denied");
          setState(() => _isLoading = false);
          return;
        }
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _currentPosition = latLng;
          _isLoading = false;
          _updateMarkers();
        });

        await _cameraToPosition(latLng);
      }

      // Set up location updates
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position newPosition) {
        if (mounted) {
          final newLatLng = LatLng(newPosition.latitude, newPosition.longitude);
          setState(() {
            _currentPosition = newLatLng;
            _updateMarkers();
          });

          // Only update camera if not navigating to avoid disrupting navigation view
          if (!_isNavigating) {
            _cameraToPosition(newLatLng);
          } else {
            _updateNavigationCamera();
          }
        }
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadRoute(LatLng origin, LatLng destination) async {
    try {
      final points = await MapService.getPolylinePoints(
        origin: origin,
        destination: destination,
      );
      final polyline = MapService.generatePolylineFromPoints(points);

      if (mounted) {
        setState(() {
          polylines[polyline.polylineId] = polyline;
        });
      }
    } catch (e) {
      debugPrint('Error loading route: $e');
    }
  }

  // Add this method to handle search and display suggestions
  void _searchPlaces(String input) {
    // Clear previous timer if it exists
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Set a debounce to avoid too many API calls
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (input.length < 2) {
        setState(() {
          _suggestions = [];
        });
        return;
      }

      setState(() {
        _isSearching = true;
      });

      try {
        final suggestions =
            await MapService.getPlaceSuggestions(input, _currentPosition);

        if (mounted) {
          setState(() {
            _suggestions = suggestions;
            _isSearching = false;
          });
          debugPrint('Found ${suggestions.length} place suggestions');
        }
      } catch (e) {
        debugPrint('Error searching places: $e');
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    });
  }

  // Method to handle when a suggestion is selected
  Future<void> _handleSuggestionTap(PlaceSuggestion suggestion) async {
    setState(() {
      _isSearching = true;
      _suggestions = []; // Clear suggestions
      _searchController.text =
          suggestion.description; // Update the search box text
    });

    try {
      final location = await MapService.getPlaceDetails(suggestion.placeId);

      if (location != null && mounted) {
        // Update destination and clear existing routes
        setState(() {
          _destinationPosition = location; // Store the destination
          polylines.clear();
          _isSearching = false;

          // Update markers - add destination marker and keep current location marker
          _updateMarkers();
        });

        // Load route to the new location
        await _loadRoute(_currentPosition!, location);

        // Move camera to show the route
        _fitMapToShowRoute(_currentPosition!, location);
      } else {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error handling suggestion selection: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  // Method to update markers on the map
  void _updateMarkers() {
    _markers = {};

    // Add current location marker
    // if (_currentPosition != null) {
    //   _markers.add(
    //     Marker(
    //       markerId: const MarkerId('current_location'),
    //       position: _currentPosition!,
    //       icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    //       infoWindow: const InfoWindow(title: 'My Location'),
    //     ),
    //   );
    // }

    // Add destination marker if available
    if (_destinationPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: _searchController.text),
        ),
      );
    }
  }

  // Helper method to fit the map to show both origin and destination
  Future<void> _fitMapToShowRoute(LatLng origin, LatLng destination) async {
    try {
      final controller = await _mapController.future;

      // Include origin and destination in the bounds
      final bounds = LatLngBounds(
        southwest: LatLng(
          origin.latitude < destination.latitude
              ? origin.latitude
              : destination.latitude,
          origin.longitude < destination.longitude
              ? origin.longitude
              : destination.longitude,
        ),
        northeast: LatLng(
          origin.latitude > destination.latitude
              ? origin.latitude
              : destination.latitude,
          origin.longitude > destination.longitude
              ? origin.longitude
              : destination.longitude,
        ),
      );

      // Add some padding
      const padding = 100.0;
      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
    } catch (e) {
      debugPrint('Error fitting map to route: $e');
    }
  }

  // Function to cancel the route
  void _cancelRoute() {
    debugPrint('MAP_NAV: Cancelling navigation');

    // Cancel navigation timer
    if (_navigationTimer != null) {
      _navigationTimer!.cancel();
      _navigationTimer = null;
      debugPrint('MAP_NAV: Navigation timer cancelled');
    }

    setState(() {
      _destinationPosition = null;
      polylines.clear();
      _navigationSteps = [];
      _isNavigating = false;
      _currentInstructionText = '';
      _currentStepIndex = 0;
      _distanceToDestination = 0.0;
      _updateMarkers();
    });

    // Return to current location
    if (_currentPosition != null) {
      _cameraToPosition(_currentPosition!);
      debugPrint('MAP_NAV: Camera returned to current location');
    }

    debugPrint('MAP_NAV: Navigation cancelled successfully');
  }

  // Function to start navigation
  Future<void> _startNavigation() async {
    debugPrint('MAP_NAV: Starting navigation process');
    if (_currentPosition == null || _destinationPosition == null) {
      debugPrint('MAP_NAV: Cannot start - missing position data');
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a destination')));
      return;
    }

    setState(() {
      _isNavigating = true;
      _isLoading = true;
    });

    try {
      debugPrint('MAP_NAV: Fetching navigation steps...');
      _navigationSteps = await MapService.getNavigationSteps(
          origin: _currentPosition!, destination: _destinationPosition!);

      debugPrint('MAP_NAV: Got ${_navigationSteps.length} navigation steps');

      if (_navigationSteps.isNotEmpty) {
        _currentStepIndex = 0;
        _currentInstructionText = _navigationSteps[0].instruction;
        _distanceToDestination = _calculateTotalRemainingDistance();
        _hasAnnouncedNextTurn = false;

        debugPrint('MAP_NAV: Initial instruction: $_currentInstructionText');
        debugPrint('MAP_NAV: Total distance: $_distanceToDestination meters');
      } else {
        debugPrint('MAP_NAV: Warning - no navigation steps returned');
      }

      setState(() {
        _isLoading = false;
      });

      // Start monitoring location for navigation updates
      _startNavigationUpdates();

      // Show the first step instruction
      _showNavigationInstruction(isNewStep: true);

      // Zoom to show current position with appropriate heading
      _updateNavigationCamera();

      debugPrint('MAP_NAV: Navigation started successfully');
    } catch (e) {
      debugPrint('MAP_NAV: Error starting navigation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting navigation: $e')));
      setState(() {
        _isNavigating = false;
        _isLoading = false;
      });
    }
  }

  // Start location updates specifically for navigation
  void _startNavigationUpdates() {
    debugPrint('MAP_NAV: Starting location updates for navigation');

    // Cancel any existing timer
    if (_navigationTimer != null) {
      _navigationTimer!.cancel();
      debugPrint('MAP_NAV: Cancelled existing timer');
    }

    // Set up more frequent updates
    _navigationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_currentPosition != null && _destinationPosition != null) {
        // Calculate distance to destination
        _updateDistanceToDestination();

        // Only log every 2 seconds to avoid flooding logs
        if (_.tick % 4 == 0) {
          debugPrint(
              'MAP_NAV: Distance to destination: ${_distanceToDestination.toStringAsFixed(2)}m');
        }

        // Check if we've reached the destination (within 20 meters)
        if (_distanceToDestination < 20) {
          debugPrint('MAP_NAV: DESTINATION REACHED!');
          _navigationArrived();
        }
        // Check if we should move to the next navigation step
        else {
          _checkForStepProgress();

          // Update camera orientation every few seconds if navigating
          if (_.tick % 6 == 0) {
            // Every 3 seconds
            _updateNavigationCamera();
            _updateRoutePolyline();
          }
        }
      }
    });
  }

  Future<void> _updateRoutePolyline() async {
    if (_currentPosition != null && _destinationPosition != null) {
      final points = await MapService.getPolylinePoints(
        origin: _currentPosition!,
        destination: _destinationPosition!,
      );
      final polyline = MapService.generatePolylineFromPoints(points);
      if (mounted) {
        setState(() {
          polylines[polyline.polylineId] = polyline;
        });
      }
    }
  }

  // Update the distance to destination
  void _updateDistanceToDestination() {
    if (_currentPosition == null || _destinationPosition == null) return;

    double distanceInMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _destinationPosition!.latitude,
      _destinationPosition!.longitude,
    );

    setState(() {
      _distanceToDestination = distanceInMeters;
    });
  }

  // Calculate the total remaining distance through all remaining steps
  double _calculateTotalRemainingDistance() {
    if (_navigationSteps.isEmpty ||
        _currentStepIndex >= _navigationSteps.length) {
      return 0.0;
    }

    double totalDistance = 0.0;

    // Add distance from current position to the start of current step
    if (_currentPosition != null) {
      totalDistance += Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _navigationSteps[_currentStepIndex].startLocation.latitude,
        _navigationSteps[_currentStepIndex].startLocation.longitude,
      );
    }

    // Add distances of all remaining steps
    for (int i = _currentStepIndex; i < _navigationSteps.length; i++) {
      totalDistance += _navigationSteps[i].distanceValue;
    }

    return totalDistance;
  }

  // Update the navigation camera dynamically during navigation
  Future<void> _updateNavigationCamera() async {
    if (!_isNavigating || _currentPosition == null) return;

    try {
      final controller = await _mapController.future;

      // Get bearing to next step or destination
      double bearing = 0;
      if (_currentStepIndex < _navigationSteps.length) {
        final targetPoint = _navigationSteps[_currentStepIndex].endLocation;

        bearing = Geolocator.bearingBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          targetPoint.latitude,
          targetPoint.longitude,
        );

        debugPrint('MAP_NAV: Camera bearing to next step: $bearing');
      }

      // Calculate zoom based on distance
      double zoom = 19.0; // Very close default zoom
      double tilt = 60.0; // Looking ahead

      // If distance to destination is large, zoom out more
      if (_distanceToDestination > 1000) {
        zoom = 16.0;
        tilt = 45.0;
      } else if (_distanceToDestination > 500) {
        zoom = 17.0;
        tilt = 50.0;
      } else if (_distanceToDestination > 200) {
        zoom = 18.0;
        tilt = 55.0;
      }

      debugPrint('MAP_NAV: Camera update - zoom: $zoom, tilt: $tilt');

      // Animate camera with proper bearing and tilt for navigation
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentPosition!,
            zoom: zoom,
            tilt: tilt,
            bearing: bearing,
          ),
        ),
      );
    } catch (e) {
      debugPrint('MAP_NAV: Error updating navigation camera: $e');
    }
  }

  // Check if we should progress to the next navigation step
  void _checkForStepProgress() {
    debugPrint('MAP_NAV: Checking for step progress...');
    if (_navigationSteps.isEmpty ||
        _currentStepIndex >= _navigationSteps.length - 1) {
      debugPrint('MAP_NAV: No more steps to check or empty steps list');
      return;
    }

    // Get the end location of the current step
    final LatLng endOfCurrentStep =
        _navigationSteps[_currentStepIndex].endLocation;

    // Calculate distance to the end of the current step
    double distanceToEndOfStep = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      endOfCurrentStep.latitude,
      endOfCurrentStep.longitude,
    );

    debugPrint(
        'MAP_NAV: Distance to end of step ${_currentStepIndex + 1}: ${distanceToEndOfStep.toStringAsFixed(2)}m');

    // Announce upcoming turn when approaching it (100m before the turn)
    if (distanceToEndOfStep < 100 &&
        !_hasAnnouncedNextTurn &&
        _currentStepIndex < _navigationSteps.length - 1) {
      debugPrint('MAP_NAV: Approaching turn, announcing next direction');
      _hasAnnouncedNextTurn = true;
      _announceNextTurn();
    }

    // If we're close to the end of the current step, move to the next one
    if (distanceToEndOfStep < 20) {
      debugPrint(
          'MAP_NAV: Reached end of step ${_currentStepIndex + 1}, advancing to next step');
      setState(() {
        _currentStepIndex++;
        if (_currentStepIndex < _navigationSteps.length) {
          _currentInstructionText =
              _navigationSteps[_currentStepIndex].instruction;
          _showNavigationInstruction(isNewStep: true);
          _hasAnnouncedNextTurn = false;
        }
      });
    }
  }

  // Add this method to announce upcoming turns
  void _announceNextTurn() {
    if (_currentStepIndex >= _navigationSteps.length - 1) return;

    final nextStep = _navigationSteps[_currentStepIndex + 1];
    final instruction = nextStep.instruction;

    debugPrint('MAP_NAV: ANNOUNCEMENT - ${instruction.toUpperCase()}');

    // Here you would typically use text-to-speech to announce the turn
    // For now, we'll just show a special snackbar

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.volume_up, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Upcoming: $instruction',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Update the _showNavigationInstruction method
  void _showNavigationInstruction({bool isNewStep = false}) {
    if (!_isNavigating ||
        _navigationSteps.isEmpty ||
        _currentStepIndex >= _navigationSteps.length) {
      debugPrint('MAP_NAV: Cannot show instruction - invalid state');
      return;
    }

    final step = _navigationSteps[_currentStepIndex];
    debugPrint(
        'MAP_NAV: Showing instruction for step ${_currentStepIndex + 1}: ${step.instruction}');

    // Only show snackbar for new steps
    if (isNewStep) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.instruction,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('${step.distance} • ${step.duration}'),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 4),
        ),
      );

      // In a real app, you would use text-to-speech here to announce the instruction
      debugPrint('MAP_NAV: VOICE GUIDANCE - ${step.instruction.toUpperCase()}');
    }
  }

  // Handle arrival at destination
  void _navigationArrived() {
    // Cancel navigation timer
    if (_navigationTimer != null) {
      _navigationTimer!.cancel();
      _navigationTimer = null;
    }

    setState(() {
      _isNavigating = false;
    });

    // Show arrival message
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You have arrived at your destination!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // Get the formatted remaining distance
  String getFormattedRemainingDistance() {
    if (_distanceToDestination < 1000) {
      return '${_distanceToDestination.round()} m';
    } else {
      return '${(_distanceToDestination / 1000).toStringAsFixed(1)} km';
    }
  }

  Future<void> _cameraToPosition(LatLng position) async {
    try {
      final controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: 15),
      ));
    } catch (e) {
      debugPrint('Error animating camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        'MAP_SCREEN: Building UI, isLoading: $_isLoading, isNavigating: $_isNavigating');

    return Scaffold(
      body: Stack(
        children: [
          // Map widget
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _currentPosition == null
                  ? const Center(child: Text("Could not get location"))
                  : GoogleMap(
                      onMapCreated: (controller) {
                        debugPrint('MAP_SCREEN: Map created');
                        if (!_mapController.isCompleted) {
                          _mapController.complete(controller);
                        }
                      },
                      initialCameraPosition:
                          CameraPosition(target: _currentPosition!, zoom: 15),
                      polylines: Set<Polyline>.of(polylines.values),
                      markers: _markers,
                      mapToolbarEnabled: false,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      zoomGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      rotateGesturesEnabled: false,
                      scrollGesturesEnabled: false,
                    ),

          // Search bar (keep this for searching destinations)
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    spreadRadius: 2,
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search places...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isSearching
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: Padding(
                            padding: EdgeInsets.all(6.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            debugPrint('MAP_SCREEN: Clearing search text');
                            _searchController.clear();
                            setState(() => _suggestions = []);
                          },
                        ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onChanged: _searchPlaces,
              ),
            ),
          ),

          // Suggestions list (keep this for search functionality)
          if (_suggestions.isNotEmpty)
            Positioned(
              top: 110,
              left: 20,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.5),
                      spreadRadius: 2,
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(
                        _suggestions[index].description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _handleSuggestionTap(_suggestions[index]),
                    );
                  },
                ),
              ),
            ),

          // Simplified navigation info panel
          if (_destinationPosition != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  debugPrint('MAP_NAV: Navigation panel tapped');
                  if (_isNavigating) {
                    _cancelRoute();
                  } else {
                    _startNavigation();
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _isNavigating ? Colors.blue.shade800 : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 7,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              color: _isNavigating ? Colors.white : Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _searchController.text,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _isNavigating
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Distance remaining
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.directions_walk,
                                color:
                                    _isNavigating ? Colors.white : Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                getFormattedRemainingDistance(),
                                style: TextStyle(
                                  color: _isNavigating
                                      ? Colors.white
                                      : Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                          // Action text
                          Text(
                            _isNavigating ? 'Tap to cancel' : 'Tap to start',
                            style: TextStyle(
                              color: _isNavigating
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),

                      // Current instruction when navigating
                      if (_isNavigating &&
                          _navigationSteps.isNotEmpty &&
                          _currentStepIndex < _navigationSteps.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_currentStepIndex + 1}',
                                  style: TextStyle(
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _currentInstructionText,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
