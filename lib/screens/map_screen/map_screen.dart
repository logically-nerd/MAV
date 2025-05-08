import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import '../../services/map_service/map_service.dart';
import 'package:flutter_google_street_view/flutter_google_street_view.dart' as street_view;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapService _mapService = MapService();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  gmaps.GoogleMapController? _mapController;
  street_view.StreetViewController? _streetViewController;
  gmaps.LatLng? _currentPosition;
  gmaps.LatLng? _sourcePosition;
  gmaps.LatLng? _destinationPosition;
  Set<gmaps.Polyline> _polylines = {};
  bool _isLoading = true;
  bool _isStreetViewActive = false;
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
          _currentPosition = gmaps.LatLng(position.latitude, position.longitude);
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

  void _moveCamera(gmaps.LatLng position) {
    _mapController?.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(position, 15),
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
            gmaps.Polyline(
              polylineId: const gmaps.PolylineId('route'),
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
        setState(() => _sourcePosition = gmaps.LatLng(lat, lng));
      }
    }
  }

  void _onDestinationChanged(String value) {
    final parts = value.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) {
        setState(() => _destinationPosition = gmaps.LatLng(lat, lng));
      }
    }
  }

  void _toggleStreetView() {
    setState(() {
      _isStreetViewActive = !_isStreetViewActive;
    });
  }

  void _onStreetViewCreated(street_view.StreetViewController controller)  async{
    _streetViewController = controller;
    
    await controller.animateTo(
      duration: 750,
      camera: street_view.StreetViewPanoramaCamera(
        bearing: 80, 
        tilt: 10, 
        zoom: 1
      )
    );
    
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
            else if (_isStreetViewActive && _currentPosition != null)
              street_view.FlutterGoogleStreetView(
               /**
                 * Setting initial position based on current location
                 */
                initPos: street_view.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                
                /**
                 * Filter panorama to outdoor only
                 */
                initSource: street_view.StreetViewSource.outdoor,

                /**
                 * Initial camera bearing (direction)
                 */
                initBearing: 30,
                
                /**
                 * Initial camera tilt
                 */
                initTilt: 0,

                /**
                 * Initial zoom level
                 */
                initZoom: 1.0,

                /**
                 * Enable/disable various controls
                 */
                zoomGesturesEnabled: true,
                panningGesturesEnabled: false,
                streetNamesEnabled: true,
                userNavigationEnabled: true,
                // compassEnabled: true,

                /**
                 * Controller to manipulate street view after initialization
                 */
                onStreetViewCreated: _onStreetViewCreated,
 
              )
            else
              gmaps.GoogleMap(
                initialCameraPosition: gmaps.CameraPosition(
                  target: _currentPosition!,
                  zoom: 15,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                polylines: _polylines,
                markers: {
                  if (_sourcePosition != null)
                    gmaps.Marker(
                      markerId: const gmaps.MarkerId('source'),
                      position: _sourcePosition!,
                      infoWindow: const gmaps.InfoWindow(title: 'Source'),
                      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                        gmaps.BitmapDescriptor.hueGreen,
                      ),
                    ),
                  if (_destinationPosition != null)
                    gmaps.Marker(
                      markerId: const gmaps.MarkerId('destination'),
                      position: _destinationPosition!,
                      infoWindow: const gmaps.InfoWindow(title: 'Destination'),
                      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                        gmaps.BitmapDescriptor.hueRed,
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
                      Row(
                        children: [
                          Expanded(
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
                    ],
                  ),
                ),
              ),
            ),
            // 360° Street View Toggle Button
            Positioned(
              bottom: 100,
              right: 12,
              child: FloatingActionButton(
                heroTag: "streetViewToggleBtn",
                backgroundColor: _isStreetViewActive ? Colors.blue : Colors.white,
                onPressed: _toggleStreetView,
                tooltip: '360° View',
                child: Icon(
                  Icons.view_in_ar,
                  color: _isStreetViewActive ? Colors.white : Colors.black87,
                ),
              ),
            ),
            // Back Button when in Street View
            if (_isStreetViewActive)
              Positioned(
                top: 16,
                left: 16,
                child: FloatingActionButton(
                  mini: true,
                  heroTag: "backToMapBtn",
                  backgroundColor: Colors.white,
                  onPressed: _toggleStreetView,
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.black87,
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
    _streetViewController?.dispose();
    _sourceController.dispose();
    _destinationController.dispose();
    super.dispose();
  }
}