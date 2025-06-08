import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/map_service.dart';
import '../services/navigation_handler.dart';
import '../services/tts_service.dart';
import 'dart:math';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final TtsService _ttsService = TtsService.instance;
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  Map<PolylineId, Polyline> polylines = {};
  Set<Marker> _markers = {};

  LatLng? _currentPosition, _destinationPosition;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  bool _isNavigating = false;
  List<NavigationStep> _navigationSteps = [];
  String _currentInstructionText = '';
  int _currentStepIndex = 0;
  Timer? _navigationTimer;
  double _distanceToDestination = 0.0;
  bool _hasAnnouncedNextTurn = false;

  // Direction tracking variables
  double _previousDistanceToDestination = 0.0;
  int _wrongDirectionCounter = 0;
  bool _hasWarnedWrongDirection = false;
  int _wrongDirectionThreshold = 4;
  double _wrongDirectionMinDeviation = 2.0;

  // Off-route tracking variables
  bool _isOffRoute = false;
  int _offRouteCounter = 0;
  final int _offRouteThreshold = 6;
  final double _offRouteDistance = 30.0;

  bool _isMapInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeMapScreen();
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeMapScreen() async {
    print('MAP_SCREEN: Initializing map screen...');

    // Initialize TTS service
    try {
      await _ttsService.init();
      print('MAP_SCREEN: TTS initialized');
    } catch (e) {
      print('MAP_SCREEN: TTS initialization error: $e');
    }

    // Initialize location
    await _getCurrentLocation();

    // Initialize navigation handler
    await NavigationHandler.instance.preload();

    print('MAP_SCREEN: Map screen initialization complete');
  }

  void _registerNavigationCallbacks() {
    print('MAP_SCREEN: Registering navigation callbacks');

    NavigationHandler.instance.registerCallbacks(
      onDestinationFound: (location, name) {
        print('MAP_SCREEN: Setting destination from voice: $name at $location');
        setState(() {
          _destinationPosition = location;
          _searchController.text = name;
          _updateMarkers();
        });

        if (_currentPosition != null) {
          _loadRoute(_currentPosition!, location).then((_) {
            _fitMapToShowRoute(_currentPosition!, location);
          });
        }
      },
      onNavigationStart: () {
        print('MAP_SCREEN: Starting navigation from voice command');
        if (_destinationPosition != null && _currentPosition != null) {
          _startNavigation();
        } else {
          print('MAP_SCREEN: Cannot start navigation - missing position data');
          _ttsService.speak(
              "Cannot start navigation. Please set a destination first.",
              TtsPriority.conversation);
        }
      },
      onNavigationStop: () {
        print('MAP_SCREEN: Stopping navigation from voice command');
        _cancelRoute();
      },
    );

    _ttsService.speak("Map system ready for voice commands", TtsPriority.map);
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
      print('Error getting location: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadRoute(LatLng origin, LatLng destination) async {
    try {
      print('MAP_SCREEN: Loading route from $origin to $destination');

      final points = await MapService.getPolylinePoints(
        origin: origin,
        destination: destination,
      );

      if (points.isNotEmpty) {
        final polyline = MapService.generatePolylineFromPoints(points);

        if (mounted) {
          setState(() {
            polylines[polyline.polylineId] = polyline;
          });
          print('MAP_SCREEN: Polyline added with ${points.length} points');
        }
      } else {
        print('MAP_SCREEN: No polyline points received');
      }
    } catch (e) {
      print('Error loading route: $e');
    }
  }

  void _updateMarkers() {
    _markers = {};

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
      print('MAP_SCREEN: Fitting map to show route');

      final controller = await _mapController.future;

      double minLat = min(origin.latitude, destination.latitude);
      double maxLat = max(origin.latitude, destination.latitude);
      double minLng = min(origin.longitude, destination.longitude);
      double maxLng = max(origin.longitude, destination.longitude);

      double latPadding = max(0.002, (maxLat - minLat) * 0.2);
      double lngPadding = max(0.002, (maxLng - minLng) * 0.2);

      final bounds = LatLngBounds(
        southwest: LatLng(minLat - latPadding, minLng - lngPadding),
        northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
      );

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100.0),
      );

      print('MAP_SCREEN: Camera animation completed');
    } catch (e) {
      print('Error fitting map to route: $e');
      try {
        final controller = await _mapController.future;
        final centerLat = (origin.latitude + destination.latitude) / 2;
        final centerLng = (origin.longitude + destination.longitude) / 2;

        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(centerLat, centerLng),
              zoom: 14.0,
            ),
          ),
        );
      } catch (fallbackError) {
        print('Fallback camera positioning also failed: $fallbackError');
      }
    }
  }

  void _cancelRoute() {
    print('MAP_NAV: Cancelling navigation');

    _navigationTimer?.cancel();
    _navigationTimer = null;

    setState(() {
      _destinationPosition = null;
      polylines.clear();
      _navigationSteps = [];
      _isNavigating = false;
      _currentInstructionText = '';
      _currentStepIndex = 0;
      _distanceToDestination = 0.0;
      _isOffRoute = false;
      _offRouteCounter = 0;
      _wrongDirectionCounter = 0;
      _hasWarnedWrongDirection = false;
      _hasAnnouncedNextTurn = false;
      _updateMarkers();
    });

    _updateNavigationState();

    if (_currentPosition != null) {
      _cameraToPosition(_currentPosition!);
    }

    print('MAP_NAV: Navigation cancelled successfully');
  }

  Future<void> _startNavigation() async {
    print('MAP_NAV: Starting navigation process');
    if (_currentPosition == null || _destinationPosition == null) {
      print('MAP_NAV: Cannot start - missing position data');
      _ttsService.speak(
          "Cannot start navigation. Please set a destination first.",
          TtsPriority.conversation);
      return;
    }

    setState(() {
      _isNavigating = true;
      _isLoading = true;
      _previousDistanceToDestination = 0.0;
      _wrongDirectionCounter = 0;
      _hasWarnedWrongDirection = false;
      _isOffRoute = false;
      _offRouteCounter = 0;
    });

    _updateNavigationState();

    try {
      print('MAP_NAV: Fetching navigation steps...');
      _navigationSteps = await MapService.getNavigationSteps(
          origin: _currentPosition!, destination: _destinationPosition!);

      print('MAP_NAV: Got ${_navigationSteps.length} navigation steps');

      if (_navigationSteps.isNotEmpty) {
        _currentStepIndex = 0;
        _currentInstructionText = _navigationSteps[0].instruction;
        _distanceToDestination = MapService.calculateTotalRemainingDistance(
          _currentPosition!,
          _navigationSteps,
          _currentStepIndex,
        );
        _hasAnnouncedNextTurn = false;

        print('MAP_NAV: Initial instruction: $_currentInstructionText');
        print('MAP_NAV: Total distance: $_distanceToDestination meters');
      } else {
        print('MAP_NAV: Warning - no navigation steps returned');
      }

      setState(() {
        _isLoading = false;
      });

      _startNavigationUpdates();
      _showNavigationInstruction(isNewStep: true);
      _updateNavigationCamera();

      print('MAP_NAV: Navigation started successfully');
    } catch (e) {
      print('MAP_NAV: Error starting navigation: $e');
      _ttsService.speak("Error starting navigation. Please try again.",
          TtsPriority.conversation);
      setState(() {
        _isNavigating = false;
        _isLoading = false;
      });
      _updateNavigationState();
    }
  }

  void _startNavigationUpdates() {
    print('MAP_NAV: Starting location updates for navigation');

    _navigationTimer?.cancel();

    _navigationTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_currentPosition != null &&
          _destinationPosition != null &&
          _isNavigating) {
        _updateDistanceToDestination();
        _checkIfOffRoute();

        if (timer.tick % 4 == 0) {
          print(
              'MAP_NAV: Distance to destination: ${_distanceToDestination.toStringAsFixed(2)}m');
        }

        if (MapService.hasReachedDestination(
            _currentPosition!, _destinationPosition!)) {
          print('MAP_NAV: DESTINATION REACHED!');
          _navigationArrived();
        } else {
          _checkForStepProgress();

          if (timer.tick % 6 == 0) {
            _updateNavigationCamera();
            _updateRoutePolyline();
          }
        }
      }
    });
  }

  Future<void> _updateRoutePolyline() async {
    if (_currentPosition != null && _destinationPosition != null) {
      try {
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
      } catch (e) {
        print('Error updating route polyline: $e');
      }
    }
  }

  void _updateDistanceToDestination() {
    if (_currentPosition == null || _destinationPosition == null) return;

    double distanceInMeters =
        MapService.calculateDistance(_currentPosition!, _destinationPosition!);

    if (_previousDistanceToDestination > 0 &&
        distanceInMeters > _previousDistanceToDestination &&
        _isNavigating) {
      double deviation = distanceInMeters - _previousDistanceToDestination;

      if (deviation > _wrongDirectionMinDeviation) {
        _wrongDirectionCounter++;
        print(
            'MAP_NAV: Possible wrong direction detected. Counter: $_wrongDirectionCounter, Deviation: ${deviation.toStringAsFixed(2)}m');
      }

      if (_wrongDirectionCounter >= _wrongDirectionThreshold &&
          !_hasWarnedWrongDirection) {
        _warnWrongDirection();
        _hasWarnedWrongDirection = true;
        _wrongDirectionCounter = 0;

        Future.delayed(const Duration(seconds: 20), () {
          if (mounted) {
            setState(() {
              _hasWarnedWrongDirection = false;
            });
          }
        });
      }
    } else {
      if (_wrongDirectionCounter > 0 &&
          distanceInMeters < _previousDistanceToDestination) {
        _wrongDirectionCounter = 0;
        print(
            'MAP_NAV: Back on the right track, reset wrong direction counter');
      }
    }

    _previousDistanceToDestination = distanceInMeters;

    setState(() {
      _distanceToDestination = distanceInMeters;
    });
  }

  void _warnWrongDirection() {
    if (!_isNavigating) return;

    print('MAP_NAV: WARNING - User moving in wrong direction!');

    double bearing = 0;
    String directionText = "turn around";

    if (_currentStepIndex < _navigationSteps.length) {
      final targetPoint = _navigationSteps[_currentStepIndex].endLocation;
      bearing = MapService.calculateBearing(_currentPosition!, targetPoint);
      directionText = _getDirectionFromBearing(bearing);
    }

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

    _speakDirections(
        "You're going in the wrong direction. Please $directionText");
  }

  String _getDirectionFromBearing(double bearing) {
    bearing = (bearing + 360) % 360;

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
    if (_navigationSteps.isEmpty ||
        _currentStepIndex >= _navigationSteps.length - 1) {
      return;
    }

    final LatLng endOfCurrentStep =
        _navigationSteps[_currentStepIndex].endLocation;
    double distanceToEndOfStep =
        MapService.calculateDistance(_currentPosition!, endOfCurrentStep);

    if (MapService.isApproachingTurn(_currentPosition!, endOfCurrentStep) &&
        !_hasAnnouncedNextTurn &&
        _currentStepIndex < _navigationSteps.length - 1) {
      print('MAP_NAV: Approaching turn, announcing next direction');
      _hasAnnouncedNextTurn = true;
      _announceNextTurn();
    }

    if (MapService.hasReachedStepEnd(_currentPosition!, endOfCurrentStep)) {
      print(
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

    final announcementText = "In $distance, $instruction";

    print('MAP_NAV: ANNOUNCEMENT - ${instruction.toUpperCase()}');

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
      return;
    }

    final step = _navigationSteps[_currentStepIndex];
    print(
        'MAP_NAV: Showing instruction for step ${_currentStepIndex + 1}: ${step.instruction}');

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
      print('MAP_NAV: VOICE GUIDANCE - ${step.instruction.toUpperCase()}');
    }
  }

  void _navigationArrived() {
    _navigationTimer?.cancel();
    _navigationTimer = null;

    setState(() {
      _isNavigating = false;
    });
    _updateNavigationState();

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 You have arrived at your destination!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 5),
      ),
    );
    _speakDirections("Congratulations! You have arrived at your destination.");
  }

  void _checkIfOffRoute() {
    if (!_isNavigating || _currentPosition == null || _navigationSteps.isEmpty)
      return;

    if (_currentStepIndex < _navigationSteps.length) {
      final currentStep = _navigationSteps[_currentStepIndex];

      double distanceToRoute = _calculateDistanceToRouteSegment(
          _currentPosition!,
          currentStep.startLocation,
          currentStep.endLocation);

      if (distanceToRoute > _offRouteDistance) {
        _offRouteCounter++;
        print(
            'MAP_NAV: Possibly off route. Counter: $_offRouteCounter, Distance from route: ${distanceToRoute.toStringAsFixed(2)}m');

        if (_offRouteCounter >= _offRouteThreshold && !_isOffRoute) {
          _isOffRoute = true;
          _handleOffRouteRerouting();
        }
      } else {
        if (_offRouteCounter > 0) {
          _offRouteCounter = 0;
          _isOffRoute = false;
          print('MAP_NAV: Back on route, reset off-route counter');
        }
      }
    }
  }

  double _calculateDistanceToRouteSegment(
      LatLng position, LatLng segmentStart, LatLng segmentEnd) {
    double distanceToStart =
        MapService.calculateDistance(position, segmentStart);
    double distanceToEnd = MapService.calculateDistance(position, segmentEnd);
    double segmentLength =
        MapService.calculateDistance(segmentStart, segmentEnd);

    if (segmentLength < 5) {
      return min(distanceToStart, distanceToEnd);
    }

    double p = (distanceToStart + distanceToEnd + segmentLength) / 2;
    double area = sqrt(
        p * (p - distanceToStart) * (p - distanceToEnd) * (p - segmentLength));

    return (2 * area) / segmentLength;
  }

  Future<void> _handleOffRouteRerouting() async {
    if (!_isNavigating || _destinationPosition == null) return;

    print('MAP_NAV: Handling off-route rerouting');

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

    await _speakDirections(
        "You appear to be off route. Recalculating directions.");

    try {
      print('MAP_NAV: Fetching new route from current position to destination');
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

        await _updateRoutePolyline();
        _showNavigationInstruction(isNewStep: true);

        print(
            'MAP_NAV: Route successfully recalculated with ${newSteps.length} steps');
      } else {
        print('MAP_NAV: Failed to get new navigation steps');
      }
    } catch (e) {
      print('MAP_NAV: Error during rerouting: $e');
    }
  }

  Future<void> _updateNavigationCamera() async {
    if (!_isNavigating || _currentPosition == null) return;

    try {
      final controller = await _mapController.future;

      double bearing = 0;
      if (_currentStepIndex < _navigationSteps.length) {
        final targetPoint = _navigationSteps[_currentStepIndex].endLocation;
        bearing = MapService.calculateBearing(_currentPosition!, targetPoint);
      }

      double zoom = 19.0;
      double tilt = 60.0;

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
      print('MAP_NAV: Error updating navigation camera: $e');
    }
  }

  Future<void> _cameraToPosition(LatLng position) async {
    try {
      final controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: 15),
      ));
    } catch (e) {
      print('Error animating camera: $e');
    }
  }

  void _updateNavigationState() {
    NavigationHandler.instance.updateNavigationState(_isNavigating);
  }

  Future<void> _speakDirections(String instruction) async {
    print('MAP_NAV: Speaking - $instruction');

    try {
      Completer<void> completer = Completer<void>();

      _ttsService.speak(
        instruction,
        TtsPriority.map,
        onComplete: () {
          completer.complete();
        },
      );

      await completer.future;
    } catch (e) {
      print('MAP_NAV: TTS error: $e');
    }
  }

  String getFormattedRemainingDistance() {
    return MapService.formatDistance(_distanceToDestination);
  }

  @override
  Widget build(BuildContext context) {
    print(
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
                        print('MAP_SCREEN: Map created');
                        try {
                          if (!_mapController.isCompleted) {
                            _mapController.complete(controller);
                            print(
                                'MAP_SCREEN: Controller completed successfully');

                            setState(() {
                              _isMapInitialized = true;
                            });

                            // Register callbacks only after map is created
                            _registerNavigationCallbacks();
                          }
                        } catch (e) {
                          print('MAP_SCREEN: Error completing controller: $e');
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

          // Navigation info panel
          if (_destinationPosition != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
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
                              color:
                                  _isNavigating ? Colors.white : Colors.black87,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.directions_walk,
                              color: _isNavigating ? Colors.white : Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              getFormattedRemainingDistance(),
                              style: TextStyle(
                                color:
                                    _isNavigating ? Colors.white : Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
        ],
      ),
    );
  }
}
