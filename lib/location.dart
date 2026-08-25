import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
// import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart';

import 'package:petrol_finder_app/common.dart';

class RouteService {
  final String apiKey;
  RouteService(this.apiKey);

  Future<Map<String, dynamic>> route(
    double olat,
    double olon,
    double dlat,
    double dlon,
  ) async {
    final r = await http.post(
      Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters',
      },
      body: jsonEncode({
        'origin': {
          'location': {
            'latLng': {'latitude': olat, 'longitude': olon},
          },
        },
        'destination': {
          'location': {
            'latLng': {'latitude': dlat, 'longitude': dlon},
          },
        },
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE',
        'computeAlternativeRoutes': false,
        'units': 'IMPERIAL',
      }),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw HttpException('Routes API ${r.statusCode}');
    }
    final j = jsonDecode(r.body);
    final route = (j['routes'] as List).first;
    return {
      'distanceMeters': route['distanceMeters'],
      'duration': route['duration'],
    };
  }
}

// Future<Position> currentPosition() async {
//   if (!await Geolocator.isLocationServiceEnabled())
//     throw Exception('Location services are disabled.');
//   var p = await Geolocator.checkPermission();
//   if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
//   if (p == LocationPermission.denied || p == LocationPermission.deniedForever)
//     throw Exception('Location permission is required.');
//   return Geolocator.getCurrentPosition(
//       locationSettings:
//           const LocationSettings(accuracy: LocationAccuracy.high));
// }

Future<LatLong> currentPosition() async {
  Location location = Location();

  // bool serviceEnabled;
  PermissionStatus permissionGranted;
  LocationData locationData;

  // serviceEnabled = await location.serviceEnabled();
  // if (!serviceEnabled) {
  //   serviceEnabled = await location.requestService();
  //   if (!serviceEnabled) {
  //     throw Exception('Location services are disabled.');
  //   }
  // }

  permissionGranted = await location.hasPermission();
  if (permissionGranted == PermissionStatus.denied) {
    permissionGranted = await location.requestPermission();
    if (permissionGranted != PermissionStatus.granted) {
      throw Exception('Location permission is required.');
    }
  }

  locationData = await location.getLocation();
  return LatLong(
    locationData.latitude,
    locationData.longitude,
    locationData.accuracy,
  );
}
