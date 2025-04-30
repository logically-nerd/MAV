// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import '../../services/map_service/map_service.dart';

// class MapScreen extends StatefulWidget {
//   const MapScreen({super.key});

//   @override
//   State<MapScreen> createState() => _MapScreenState();
// }

// class _MapScreenState extends State<MapScreen> {
//   final MapService _mapService = MapService();
//   final TextEditingController _searchController = TextEditingController();
//   bool _isLoading = true;
//   bool _isSearching = false;
//   List<Place> _searchResults = [];
//   bool _showResults = false;
//   FocusNode _searchFocusNode = FocusNode();
//   String? _errorMessage;

//   @override
//   void initState() {
//     super.initState();
//     _initializeMap();
//     _searchFocusNode.addListener(_onFocusChange);
//   }

//   void _onFocusChange() {
//     setState(() {
//       _showResults = _searchFocusNode.hasFocus && _searchResults.isNotEmpty;
//     });
//   }

//   Future<void> _initializeMap() async {
//     try {
//       await _mapService.initialize();
//       setState(() {
//         _isLoading = false;
//       });
//     } catch (e) {
//       setState(() {
//         _errorMessage = 'Failed to initialize map: $e';
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _handleSearch() async {
//     if (_searchController.text.isEmpty) {
//       setState(() {
//         _searchResults = [];
//         _showResults = false;
//         _errorMessage = null;
//       });
//       return;
//     }

//     setState(() {
//       _isSearching = true;
//       _errorMessage = null;
//     });

//     try {
//       final results =
//           await _mapService.searchNearbyPlaces(_searchController.text);
//       setState(() {
//         _searchResults = results;
//         _showResults = true;
//         _isSearching = false;
//         if (results.isEmpty) {
//           _errorMessage = 'No places found';
//         }
//       });
//     } catch (e) {
//       setState(() {
//         _errorMessage = 'Error searching places: $e';
//         _isSearching = false;
//       });
//     }
//   }

//   void _selectPlace(Place place) {
//     setState(() {
//       _searchController.text = place.name;
//       _showResults = false;
//       _searchFocusNode.unfocus();
//       _errorMessage = null;
//     });

//     _mapService.addPlaceMarker(place);
//   }

//   @override
//   void dispose() {
//     _searchController.dispose();
//     _searchFocusNode.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : Stack(
//               children: [
//                 GoogleMap(
//                   initialCameraPosition: const CameraPosition(
//                     target: LatLng(0, 0),
//                     zoom: 15,
//                   ),
//                   onMapCreated: _mapService.setMapController,
//                   markers: _mapService.markers,
//                   myLocationEnabled: true,
//                   myLocationButtonEnabled: true,
//                 ),
//                 Positioned(
//                   top: 40,
//                   left: 16,
//                   right: 16,
//                   child: Column(
//                     children: [
//                       Container(
//                         padding: const EdgeInsets.symmetric(horizontal: 16),
//                         decoration: BoxDecoration(
//                           color: const Color.fromARGB(255, 112, 109, 109),
//                           borderRadius: BorderRadius.circular(8),
//                           boxShadow: [
//                             BoxShadow(
//                               color: Colors.black.withOpacity(0.1),
//                               blurRadius: 8,
//                               offset: const Offset(0, 2),
//                             ),
//                           ],
//                         ),
//                         child: Row(
//                           children: [
//                             Expanded(
//                               child: TextField(
//                                 controller: _searchController,
//                                 focusNode: _searchFocusNode,
//                                 style: const TextStyle(
//                                     color: Color.fromARGB(255, 0, 0, 0)),
//                                 decoration: InputDecoration(
//                                   hintText: 'Search places...',
//                                   hintStyle:
//                                       const TextStyle(color: Colors.black54),
//                                   border: InputBorder.none,
//                                   errorText: _errorMessage,
//                                 ),
//                                 onSubmitted: (_) => _handleSearch(),
//                               ),
//                             ),
//                             if (_isSearching)
//                               const Padding(
//                                 padding: EdgeInsets.all(8.0),
//                                 child: SizedBox(
//                                   width: 20,
//                                   height: 20,
//                                   child: CircularProgressIndicator(
//                                     strokeWidth: 2,
//                                   ),
//                                 ),
//                               )
//                             else
//                               IconButton(
//                                 icon: const Icon(Icons.search,
//                                     color: Color.fromARGB(255, 23, 22, 22)),
//                                 onPressed: _handleSearch,
//                               ),
//                           ],
//                         ),
//                       ),
//                       if (_showResults && _searchResults.isNotEmpty)
//                         Container(
//                           margin: const EdgeInsets.only(top: 8),
//                           decoration: BoxDecoration(
//                             color: const Color.fromARGB(255, 112, 109, 109),
//                             borderRadius: BorderRadius.circular(8),
//                             boxShadow: [
//                               BoxShadow(
//                                 color: Colors.black.withOpacity(0.1),
//                                 blurRadius: 8,
//                                 offset: const Offset(0, 2),
//                               ),
//                             ],
//                           ),
//                           constraints: BoxConstraints(
//                             maxHeight: MediaQuery.of(context).size.height * 0.4,
//                           ),
//                           child: ListView.builder(
//                             shrinkWrap: true,
//                             itemCount: _searchResults.length,
//                             itemBuilder: (context, index) {
//                               final place = _searchResults[index];
//                               return ListTile(
//                                 title: Text(
//                                   place.name,
//                                   style: const TextStyle(color: Colors.black),
//                                 ),
//                                 subtitle: Text(
//                                   place.address ?? '',
//                                   style: const TextStyle(color: Colors.black54),
//                                 ),
//                                 onTap: () => _selectPlace(place),
//                               );
//                             },
//                           ),
//                         ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/map_service/map_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapService _mapService = MapService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isSearching = false;
  List<Place> _searchResults = [];
  bool _showResults = false;
  FocusNode _searchFocusNode = FocusNode();
  String? _errorMessage;
  bool _showNavigationControls = false;

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _searchFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() {
      _showResults = _searchFocusNode.hasFocus && _searchResults.isNotEmpty;
    });
  }

  Future<void> _initializeMap() async {
    try {
      await _mapService.initialize();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize map: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSearch() async {
    if (_searchController.text.isEmpty) {
      setState(() {
        _searchResults = [];
        _showResults = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results =
          await _mapService.searchNearbyPlaces(_searchController.text);
      setState(() {
        _searchResults = results;
        _showResults = true;
        _isSearching = false;
        if (results.isEmpty) {
          _errorMessage = 'No places found';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error searching places: $e';
        _isSearching = false;
      });
    }
  }

  void _selectPlace(Place place) {
    setState(() {
      _searchController.text = place.name;
      _showResults = false;
      _searchFocusNode.unfocus();
      _errorMessage = null;
      _showNavigationControls = true;
    });

    _mapService.addPlaceMarker(place, moveCamera: true);
  }

  Future<void> _startNavigation() async {
    if (_searchResults.isEmpty) return;

    final selectedPlace = _searchResults.firstWhere(
      (place) => place.name == _searchController.text,
      orElse: () => _searchResults.first,
    );

    try {
      await _mapService.startNavigation(selectedPlace.location);
      setState(() {
        _showNavigationControls = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to start navigation: $e';
      });
    }
  }

  void _stopNavigation() {
    _mapService.stopNavigation();
    setState(() {
      _showNavigationControls = true;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(0, 0),
                    zoom: 15,
                  ),
                  onMapCreated: _mapService.setMapController,
                  markers: _mapService.markers,
                  polylines: _mapService.polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  compassEnabled: true,
                  zoomControlsEnabled: false,
                ),
                Positioned(
                  top: 40,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                style: const TextStyle(color: Colors.black),
                                decoration: InputDecoration(
                                  hintText: 'Search places...',
                                  hintStyle:
                                      const TextStyle(color: Colors.black54),
                                  border: InputBorder.none,
                                  errorText: _errorMessage,
                                ),
                                onSubmitted: (_) => _handleSearch(),
                              ),
                            ),
                            if (_isSearching)
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.search,
                                    color: Colors.black),
                                onPressed: _handleSearch,
                              ),
                          ],
                        ),
                      ),
                      if (_showResults && _searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.4,
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final place = _searchResults[index];
                              return ListTile(
                                title: Text(
                                  place.name,
                                  style: const TextStyle(color: Colors.black),
                                ),
                                subtitle: Text(
                                  place.address ?? '',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                onTap: () => _selectPlace(place),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (_showNavigationControls)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Start Navigation',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _startNavigation,
                    ),
                  ),
                if (_mapService.isNavigating)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Stop Navigation',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _stopNavigation,
                    ),
                  ),
              ],
            ),
    );
  }
}
