import 'dart:async';
import 'package:flutter/material.dart';
// Remove this import
// import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/map_service.dart';
import '../services/navigation_handler.dart';
import '../services/tts_service.dart'; // Add this import
import 'dart:math';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Replace the local FlutterTts with our TTS service
  // final FlutterTts _tts = FlutterTts();
  final TtsService _ttsService = TtsService.instance;

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

  // Add these variables to keep track of direction
  double _previousDistanceToDestination = 0.0;
  int _wrongDirectionCounter = 0;
  bool _hasWarnedWrongDirection = false;
  int _wrongDirectionThreshold = 4; // Reduced from 5 to be more responsive
  double _wrongDirectionMinDeviation =
      2.0; // Minimum deviation in meters to count as wrong direction

  // Add these variables to the class
  bool _isOffRoute = false;
  int _offRouteCounter = 0;
  final int _offRouteThreshold = 6; // How many checks before rerouting
  final double _offRouteDistance =
      30.0; // Distance in meters to be considered off route

  // Add this variable
  bool _isMapInitialized = false;

  Future<void> _speakDirections(String instruction) async {
    debugPrint('MAP_NAV: Speaking - $instruction');

    try {
      // Create a completer to wait for speech completion
      Completer<void> completer = Completer<void>();

      // Use the centralized TTS service with map priority
      _ttsService.speak(
        instruction,
        TtsPriority.map,
        onComplete: () {
          completer.complete();
        },
      );

      // Wait for speech to complete
      await completer.future;
    } catch (e) {
      debugPrint('MAP_NAV: TTS error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();

    // Wait to initialize navigation systems until map is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize TTS
      _initializeTTS();
    });
  }

  Future<void> _initializeTTS() async {
    try {
      // Initialize the TTS service if not already initialized
      await _ttsService.init();
      debugPrint('MAP_NAV: TTS initialization complete');
    } catch (e) {
      debugPrint('MAP_NAV: Error initializing TTS: $e');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _navigationTimer?.cancel();
    _searchController.dispose();
    // Remove direct TTS stop call - no longer needed
    // _tts.stop();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await MapService.getCurrentLocation();

      if (position != null && mounted) {
        setState(() {
          _currentPosition = position;
          _isLoading = false;
          _updateMarkers();
        });

        await _cameraToPosition(position);

        // Set up location updates
        MapService.getLocationUpdates(
          onLocationUpdate: (LatLng newPosition) {
            if (mounted) {
              setState(() {
                _currentPosition = newPosition;
                _updateMarkers();
              });

              // Only update camera if not navigating to avoid disrupting navigation view
              if (!_isNavigating) {
                _cameraToPosition(newPosition);
              } else {
                _updateNavigationCamera();
              }
            }
          },
        );
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
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

  void _updateMarkers() {
    _markers = {};

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
    _updateNavigationState();

    // Return to current location
    if (_currentPosition != null) {
      _cameraToPosition(_currentPosition!);
      debugPrint('MAP_NAV: Camera returned to current location');
    }

    debugPrint('MAP_NAV: Navigation cancelled successfully');
  }

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
      _previousDistanceToDestination = 0.0; // Reset the direction tracking
      _wrongDirectionCounter = 0;
      _hasWarnedWrongDirection = false;
    });
    _updateNavigationState();

    try {
      debugPrint('MAP_NAV: Fetching navigation steps...');
      _navigationSteps = await MapService.getNavigationSteps(
          origin: _currentPosition!, destination: _destinationPosition!);

      debugPrint('MAP_NAV: Got ${_navigationSteps.length} navigation steps');

      if (_navigationSteps.isNotEmpty) {
        _currentStepIndex = 0;
        _currentInstructionText = _navigationSteps[0].instruction;
        _distanceToDestination = MapService.calculateTotalRemainingDistance(
          _currentPosition!,
          _navigationSteps,
          _currentStepIndex,
        );
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

        // Check if we're off route
        _checkIfOffRoute();

        // Only log every 2 seconds to avoid flooding logs
        if (_.tick % 4 == 0) {
          debugPrint(
              'MAP_NAV: Distance to destination: ${_distanceToDestination.toStringAsFixed(2)}m');
        }

        // Check if we've reached the destination (within 20 meters)
        if (MapService.hasReachedDestination(
            _currentPosition!, _destinationPosition!)) {
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

  void _updateDistanceToDestination() {
    if (_currentPosition == null || _destinationPosition == null) return;

    double distanceInMeters =
        MapService.calculateDistance(_currentPosition!, _destinationPosition!);

    // Check if we're moving in the wrong direction
    if (_previousDistanceToDestination > 0 &&
        distanceInMeters > _previousDistanceToDestination &&
        _isNavigating) {
      // Calculate deviation - how much farther we've moved
      double deviation = distanceInMeters - _previousDistanceToDestination;

      // Only increment counter if the difference is significant (to filter out GPS fluctuations)
      if (deviation > _wrongDirectionMinDeviation) {
        _wrongDirectionCounter++;
        debugPrint(
            'MAP_NAV: Possible wrong direction detected. Counter: $_wrongDirectionCounter, Deviation: ${deviation.toStringAsFixed(2)}m');
      }

      // If we've detected consistent wrong movement and haven't warned
      if (_wrongDirectionCounter >= _wrongDirectionThreshold &&
          !_hasWarnedWrongDirection) {
        _warnWrongDirection();
        _hasWarnedWrongDirection = true;

        // Reset counter after warning
        _wrongDirectionCounter = 0;

        // Schedule reset of warning flag after some time (reduced to 20 seconds)
        Future.delayed(Duration(seconds: 20), () {
          if (mounted) {
            setState(() {
              _hasWarnedWrongDirection = false;
            });
          }
        });
      }
    } else {
      // Reset counter if we're moving in the right direction
      if (_wrongDirectionCounter > 0 &&
          distanceInMeters < _previousDistanceToDestination) {
        _wrongDirectionCounter = 0;
        debugPrint(
            'MAP_NAV: Back on the right track, reset wrong direction counter');
      }
    }

    // Update the previous distance
    _previousDistanceToDestination = distanceInMeters;

    setState(() {
      _distanceToDestination = distanceInMeters;
    });
  }

  void _warnWrongDirection() {
    if (!_isNavigating) return;

    debugPrint('MAP_NAV: WARNING - User moving in wrong direction!');

    // Get the bearing to the next waypoint
    double bearing = 0;
    String directionText = "turn around";

    if (_currentStepIndex < _navigationSteps.length) {
      final targetPoint = _navigationSteps[_currentStepIndex].endLocation;
      bearing = MapService.calculateBearing(_currentPosition!, targetPoint);

      // Convert bearing to a cardinal direction instruction
      directionText = _getDirectionFromBearing(bearing);
    }

    // Show snackbar with warning
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Wrong direction! Please $directionText',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );

    // Speak the warning with higher priority
    _speakDirections(
        "You're going in the wrong direction. Please $directionText");
  }

  String _getDirectionFromBearing(double bearing) {
    // Normalize bearing to 0-360
    bearing = (bearing + 360) % 360;

    // Convert bearing to a cardinal direction
    if (bearing >= 337.5 || bearing < 22.5) return "turn around and head north";
    if (bearing >= 22.5 && bearing < 67.5)
      return "turn around and head northeast";
    if (bearing >= 67.5 && bearing < 112.5) return "turn around and head east";
    if (bearing >= 112.5 && bearing < 157.5)
      return "turn around and head southeast";
    if (bearing >= 157.5 && bearing < 202.5)
      return "turn around and head south";
    if (bearing >= 202.5 && bearing < 247.5)
      return "turn around and head southwest";
    if (bearing >= 247.5 && bearing < 292.5) return "turn around and head west";
    return "turn around and head northwest";
  }

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
    double distanceToEndOfStep =
        MapService.calculateDistance(_currentPosition!, endOfCurrentStep);

    debugPrint(
        'MAP_NAV: Distance to end of step ${_currentStepIndex + 1}: ${distanceToEndOfStep.toStringAsFixed(2)}m');

    // Announce upcoming turn when approaching it (100m before the turn)
    if (MapService.isApproachingTurn(_currentPosition!, endOfCurrentStep) &&
        !_hasAnnouncedNextTurn &&
        _currentStepIndex < _navigationSteps.length - 1) {
      debugPrint('MAP_NAV: Approaching turn, announcing next direction');
      _hasAnnouncedNextTurn = true;
      _announceNextTurn();
    }

    // If we're close to the end of the current step, move to the next one
    if (MapService.hasReachedStepEnd(_currentPosition!, endOfCurrentStep)) {
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

  void _announceNextTurn() {
    if (_currentStepIndex >= _navigationSteps.length - 1) return;

    final nextStep = _navigationSteps[_currentStepIndex + 1];
    final instruction = nextStep.instruction;
    final distance = nextStep.distance;

    // Enhanced instruction with distance
    final announcementText = "In $distance, $instruction";

    debugPrint('MAP_NAV: ANNOUNCEMENT - ${instruction.toUpperCase()}');

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
    _speakDirections(announcementText);
  }

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
      _speakDirections(step.instruction);
      debugPrint('MAP_NAV: VOICE GUIDANCE - ${step.instruction.toUpperCase()}');
    }
  }

  void _navigationArrived() {
    // Cancel navigation timer
    if (_navigationTimer != null) {
      _navigationTimer!.cancel();
      _navigationTimer = null;
    }

    setState(() {
      _isNavigating = false;
    });
    _updateNavigationState();

    // Show arrival message
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You have arrived at your destination!'),
        backgroundColor: Colors.green,
      ),
    );
    _speakDirections("You have arrived at your destination");
  }

  String getFormattedRemainingDistance() {
    return MapService.formatDistance(_distanceToDestination);
  }

  Future<void> _updateNavigationCamera() async {
    if (!_isNavigating || _currentPosition == null) return;

    try {
      final controller = await _mapController.future;

      // Get bearing to next step or destination
      double bearing = 0;
      if (_currentStepIndex < _navigationSteps.length) {
        final targetPoint = _navigationSteps[_currentStepIndex].endLocation;

        bearing = MapService.calculateBearing(_currentPosition!, targetPoint);

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

  void _updateNavigationState() {
    NavigationHandler.instance.updateNavigationState(_isNavigating);
  }

  void _checkIfOffRoute() {
    if (!_isNavigating || _currentPosition == null || _navigationSteps.isEmpty)
      return;

    // Calculate deviation from current route
    // For simplicity, we'll check distance to the next waypoint
    if (_currentStepIndex < _navigationSteps.length) {
      final currentStep = _navigationSteps[_currentStepIndex];

      // Calculate the closest point on our current route segment
      double distanceToRoute = _calculateDistanceToRouteSegment(
          _currentPosition!,
          currentStep.startLocation,
          currentStep.endLocation);

      if (distanceToRoute > _offRouteDistance) {
        _offRouteCounter++;
        debugPrint(
            'MAP_NAV: Possibly off route. Counter: $_offRouteCounter, Distance from route: ${distanceToRoute.toStringAsFixed(2)}m');

        // After several consistent off-route detections, trigger a reroute
        if (_offRouteCounter >= _offRouteThreshold && !_isOffRoute) {
          _isOffRoute = true;
          _handleOffRouteRerouting();
        }
      } else {
        // Reset the counter if we're back on route
        if (_offRouteCounter > 0) {
          _offRouteCounter = 0;
          _isOffRoute = false;
          debugPrint('MAP_NAV: Back on route, reset off-route counter');
        }
      }
    }
  }

  double _calculateDistanceToRouteSegment(
      LatLng position, LatLng segmentStart, LatLng segmentEnd) {
    // Implementation using MapService.calculateDistance and vector math
    // This is a simplified version - for a real app, consider using a library

    // Calculate distance directly to both endpoints
    double distanceToStart =
        MapService.calculateDistance(position, segmentStart);
    double distanceToEnd = MapService.calculateDistance(position, segmentEnd);

    // Calculate the length of the segment
    double segmentLength =
        MapService.calculateDistance(segmentStart, segmentEnd);

    // If segment is very short, just return distance to either endpoint
    if (segmentLength < 5) {
      return min(distanceToStart, distanceToEnd);
    }

    // Use the Pythagorean theorem to get approximate perpendicular distance
    // This is a simplified calculation that works for short distances
    double p = (distanceToStart + distanceToEnd + segmentLength) / 2;
    double area = sqrt(
        p * (p - distanceToStart) * (p - distanceToEnd) * (p - segmentLength));

    return (2 * area) / segmentLength;
  }

  Future<void> _handleOffRouteRerouting() async {
    if (!_isNavigating || _destinationPosition == null) return;

    debugPrint('MAP_NAV: Handling off-route rerouting');

    // Show notification to user
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.route, color: Colors.white),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'You appear to be off route. Recalculating...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );

    // Announce rerouting
    await _speakDirections(
        "You appear to be off route. Recalculating directions.");

    try {
      // Get fresh navigation steps from current position
      debugPrint(
          'MAP_NAV: Fetching new route from current position to destination');
      final newSteps = await MapService.getNavigationSteps(
        origin: _currentPosition!,
        destination: _destinationPosition!,
      );

      if (newSteps.isNotEmpty) {
        setState(() {
          _navigationSteps = newSteps;
          _currentStepIndex = 0;
          _currentInstructionText = _navigationSteps[0].instruction;
          _isOffRoute = false;
          _offRouteCounter = 0;
          _hasAnnouncedNextTurn = false;
        });

        // Update polyline with new route
        await _updateRoutePolyline();

        // Show the first instruction
        _showNavigationInstruction(isNewStep: true);

        debugPrint(
            'MAP_NAV: Route successfully recalculated with ${newSteps.length} steps');
      } else {
        debugPrint('MAP_NAV: Failed to get new navigation steps');
      }
    } catch (e) {
      debugPrint('MAP_NAV: Error during rerouting: $e');
    }
  }

  void _registerNavigationCallbacks() {
    debugPrint('MAP_SCREEN: Registering navigation callbacks');

    NavigationHandler.instance.registerCallbacks(
      onDestinationFound: (location, name) {
        print('MAP_SCREEN: Setting destination from voice command: $name');
        setState(() {
          _destinationPosition = location;
          _searchController.text = name;
          _updateMarkers();
        });

        if (_currentPosition != null) {
          _loadRoute(_currentPosition!, location);
          _fitMapToShowRoute(_currentPosition!, location);
        }
      },
      onNavigationStart: () {
        print('MAP_SCREEN: Starting navigation from voice command');
        _startNavigation();
      },
      onNavigationStop: () {
        print('MAP_SCREEN: Stopping navigation from voice command');
        _cancelRoute();
      },
    );

    // Use TTS service for initialization message
    _ttsService.speak("Map initialized", TtsPriority.map);
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
                        try {
                          if (!_mapController.isCompleted) {
                            _mapController.complete(controller);
                            debugPrint(
                                'MAP_SCREEN: Controller completed successfully');

                            // Set flag that map is initialized and register callbacks
                            setState(() {
                              _isMapInitialized = true;
                            });

                            // Register callbacks only after map is created
                            _registerNavigationCallbacks();
                          }
                        } catch (e) {
                          debugPrint(
                              'MAP_SCREEN: Error completing controller: $e');
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
          // Positioned(
          //   top: 50,
          //   left: 20,
          //   right: 20,
          //   child: Container(
          //     decoration: BoxDecoration(
          //       color: const Color.fromARGB(255, 255, 255, 255),
          //       borderRadius: BorderRadius.circular(8),
          //       boxShadow: [
          //         BoxShadow(
          //           color: Colors.grey.withOpacity(0.5),
          //           spreadRadius: 2,
          //           blurRadius: 7,
          //           offset: const Offset(0, 3),
          //         )
          //       ],
          //     ),
          //     child: TextField(
          //       controller: _searchController,
          //       style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0)),
          //       decoration: InputDecoration(
          //         hintText: 'Search places...',
          //         prefixIcon: const Icon(Icons.search),
          //         suffixIcon: _isSearching
          //             ? const SizedBox(
          //                 width: 24,
          //                 height: 24,
          //                 child: Padding(
          //                   padding: EdgeInsets.all(6.0),
          //                   child: CircularProgressIndicator(strokeWidth: 2),
          //                 ),
          //               )
          //             : IconButton(
          //                 icon: const Icon(Icons.clear),
          //                 onPressed: () {
          //                   debugPrint('MAP_SCREEN: Clearing search text');
          //                   _searchController.clear();
          //                   setState(() => _suggestions = []);
          //                 },
          //               ),
          //         border: InputBorder.none,
          //         contentPadding: const EdgeInsets.symmetric(vertical: 15),
          //       ),
          //       onChanged: _searchPlaces,
          //     ),
          //   ),
          // ),

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
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: _isNavigating
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              maxLines: 3,
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
                                  color: const Color.fromARGB(255, 0, 0, 0),
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
                                      color: Color.fromARGB(255, 0, 0, 0),
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
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
