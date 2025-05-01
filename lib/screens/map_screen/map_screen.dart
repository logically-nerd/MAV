import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import '../../services/map_service/map_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapService _mapService = MapService();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  LatLng? _sourcePosition;
  LatLng? _destinationPosition;
  Set<Polyline> _polylines = {};
  bool _isLoading = true;
  static final String _googleApiKey = "AIzaSyAYS5gaj5OKjGHzlkeLwMch5sf69IItK60";

  // For gesture handling
  final Set<Factory<OneSequenceGestureRecognizer>> _gestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      Position position = await _mapService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _sourcePosition = _currentPosition;
          _sourceController.text =
              '${position.latitude}, ${position.longitude}';
          _isLoading = false;
        });
        _moveCamera(_currentPosition!);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching location: $e')),
        );
      }
    }
  }

  void _moveCamera(LatLng position) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 15),
    );
  }

  Future<void> _drawPolyline() async {
    if (_sourcePosition == null || _destinationPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set both source and destination')),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);
      final polylinePoints = await _mapService.getPolylinePoints(
        googleApiKey: _googleApiKey,
        origin: _sourcePosition!,
        destination: _destinationPosition!,
      );
      print(polylinePoints);
      if (mounted) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              color: Colors.blue,
              width: 5,
              points: polylinePoints,
            ),
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error drawing route: $e')),
        );
      }
    }
  }

  void _onSourceChanged(String value) {
    final parts = value.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) {
        setState(() => _sourcePosition = LatLng(lat, lng));
      }
    }
  }

  void _onDestinationChanged(String value) {
    final parts = value.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) {
        setState(() => _destinationPosition = LatLng(lat, lng));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_currentPosition == null)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Could not fetch location'),
                    TextButton(
                      onPressed: _fetchCurrentLocation,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _currentPosition!,
                  zoom: 15,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                polylines: _polylines,
                markers: {
                  if (_sourcePosition != null)
                    Marker(
                      markerId: const MarkerId('source'),
                      position: _sourcePosition!,
                      infoWindow: const InfoWindow(title: 'Source'),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueGreen,
                      ),
                    ),
                  if (_destinationPosition != null)
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: _destinationPosition!,
                      infoWindow: const InfoWindow(title: 'Destination'),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueRed,
                      ),
                    ),
                },
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                gestureRecognizers: _gestureRecognizers,
              ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _sourceController,
                        decoration: InputDecoration(
                          hintText: 'Source (lat, lng)',
                          filled: true,
                          fillColor: const Color.fromARGB(255, 0, 0, 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: _onSourceChanged,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _destinationController,
                        decoration: InputDecoration(
                          hintText: 'Destination (lat, lng)',
                          filled: true,
                          fillColor: const Color.fromARGB(255, 14, 13, 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: _onDestinationChanged,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _drawPolyline,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Show Route'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _sourceController.dispose();
    _destinationController.dispose();
    super.dispose();
  }
}
