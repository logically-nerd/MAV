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

    try {
      await _ttsService.init();
      print('MAP_SCREEN: TTS initialized');
    } catch (e) {
      print('MAP_SCREEN: TTS initialization error: $e');
    }

    await _getCurrentLocation();
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
          _ttsService.speakAndWait(
            "Cannot start navigation. Please set a destination first.",
            TtsPriority.conversation,
          );
        }
      },
      onNavigationStop: () {
        print('MAP_SCREEN: Stopping navigation from voice command');
        _cancelRoute();
      },
    );

    _ttsService.speakAndWait(
        "Map system ready for voice commands", TtsPriority.map);
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
    } catch (e) {
      print('Error fitting map to route: $e');
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
      _wrongDirectionCounter = 0;
      _hasWarnedWrongDirection = false;
      _hasAnnouncedNextTurn = false;
      _updateMarkers();
    });

    NavigationHandler.instance.updateNavigationState(false);

    if (_currentPosition != null) {
      _cameraToPosition(_currentPosition!);
    }

    print('MAP_NAV: Navigation cancelled successfully');
  }

  Future<void> _startNavigation() async {
    print('MAP_NAV: Starting navigation process');
    if (_currentPosition == null || _destinationPosition == null) {
      print('MAP_NAV: Cannot start - missing position data');
      _ttsService.speakAndWait(
        "Cannot start navigation. Please set a destination first.",
        TtsPriority.conversation,
      );
      return;
    }

    setState(() {
      _isNavigating = true;
      _previousDistanceToDestination = 0.0;
      _wrongDirectionCounter = 0;
      _hasWarnedWrongDirection = false;
    });

    NavigationHandler.instance.updateNavigationState(true);

    try {
      _navigationSteps = await MapService.getNavigationSteps(
        origin: _currentPosition!,
        destination: _destinationPosition!,
      );

      if (_navigationSteps.isNotEmpty) {
        _currentStepIndex = 0;
        _currentInstructionText = _navigationSteps[0].instruction;
        _distanceToDestination = MapService.calculateTotalRemainingDistance(
          _currentPosition!,
          _navigationSteps,
          _currentStepIndex,
        );
        _hasAnnouncedNextTurn = false;

        _startNavigationUpdates();
        _showNavigationInstruction(isNewStep: true);
        _updateNavigationCamera();
      }
    } catch (e) {
      print('MAP_NAV: Error starting navigation: $e');
      _ttsService.speakAndWait(
        "Error starting navigation. Please try again.",
        TtsPriority.conversation,
      );
      setState(() {
        _isNavigating = false;
      });
      NavigationHandler.instance.updateNavigationState(false);
    }
  }

  void _startNavigationUpdates() {
    _navigationTimer?.cancel();

    _navigationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_currentPosition != null &&
          _destinationPosition != null &&
          _isNavigating) {
        _updateDistanceToDestination();

        if (MapService.hasReachedDestination(
            _currentPosition!, _destinationPosition!)) {
          _navigationArrived();
        } else {
          _checkForStepProgress();
          _updateNavigationCamera();
        }
      }
    });
  }

  void _updateDistanceToDestination() {
    if (_currentPosition == null || _destinationPosition == null) return;

    double distanceInMeters =
        MapService.calculateDistance(_currentPosition!, _destinationPosition!);

    // Check for wrong direction
    if (_previousDistanceToDestination > 0 &&
        distanceInMeters > _previousDistanceToDestination + 5 &&
        _isNavigating) {
      _wrongDirectionCounter++;

      if (_wrongDirectionCounter >= 3 && !_hasWarnedWrongDirection) {
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
      }
    }

    _previousDistanceToDestination = distanceInMeters;

    setState(() {
      _distanceToDestination = distanceInMeters;
    });
  }

  void _warnWrongDirection() {
    if (!_isNavigating) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Wrong direction! Please turn around'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );

    _ttsService.speakAndWait(
      "You're going in the wrong direction. Please turn around",
      TtsPriority.map,
    );
  }

  void _checkForStepProgress() {
    if (_navigationSteps.isEmpty ||
        _currentStepIndex >= _navigationSteps.length - 1) {
      return;
    }

    final LatLng endOfCurrentStep =
        _navigationSteps[_currentStepIndex].endLocation;

    if (MapService.isApproachingTurn(_currentPosition!, endOfCurrentStep) &&
        !_hasAnnouncedNextTurn &&
        _currentStepIndex < _navigationSteps.length - 1) {
      _hasAnnouncedNextTurn = true;
      _announceNextTurn();
    }

    if (MapService.hasReachedStepEnd(_currentPosition!, endOfCurrentStep)) {
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

    _ttsService.speakAndWait("In $distance, $instruction", TtsPriority.map);
  }

  void _showNavigationInstruction({bool isNewStep = false}) {
    if (!_isNavigating ||
        _navigationSteps.isEmpty ||
        _currentStepIndex >= _navigationSteps.length) {
      return;
    }

    final step = _navigationSteps[_currentStepIndex];

    if (isNewStep) {
      _ttsService.speakAndWait(step.instruction, TtsPriority.map);
    }
  }

  void _navigationArrived() {
    _navigationTimer?.cancel();
    _navigationTimer = null;

    setState(() {
      _isNavigating = false;
    });
    NavigationHandler.instance.updateNavigationState(false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 You have arrived at your destination!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 5),
      ),
    );
    _ttsService.speakAndWait(
        "Congratulations! You have arrived at your destination.",
        TtsPriority.map);
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

      double zoom = _distanceToDestination > 500 ? 16.0 : 18.0;

      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentPosition!,
            zoom: zoom,
            tilt: 45.0,
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

  String getFormattedRemainingDistance() {
    return MapService.formatDistance(_distanceToDestination);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _currentPosition == null
                  ? const Center(child: Text("Could not get location"))
                  : GoogleMap(
                      onMapCreated: (controller) {
                        if (!_mapController.isCompleted) {
                          _mapController.complete(controller);
                          _registerNavigationCallbacks();
                        }
                      },
                      initialCameraPosition:
                          CameraPosition(target: _currentPosition!, zoom: 15),
                      polylines: Set<Polyline>.of(polylines.values),
                      markers: _markers,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
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
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                            color: _isNavigating ? Colors.white : Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (_isNavigating && _currentInstructionText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: Text(
                          _currentInstructionText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
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
