import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as loc;
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

Future<LatLong> currentPosition(bool headless) async {
  loc.LocationData locationData;

  // serviceEnabled = await location.serviceEnabled();
  // if (!serviceEnabled) {
  //   serviceEnabled = await location.requestService();
  //   if (!serviceEnabled) {
  //     throw Exception('Location services are disabled.');
  //   }
  // }

  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('Location services are disabled.');
  }

  // Permission checks do not require an Activity. Requesting permission does,
  // so a headless Android Auto engine must never call requestPermission().
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied && !headless) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception(
      headless
          ? 'Location permission must be granted to Petrol Finder on the phone before using Android Auto.'
          : 'Location permission is required.',
    );
  }

  // LocationPermission permissionGranted;
  // permissionGranted = await location.hasPermission();
  // if (permissionGranted == PermissionStatus.denied) {
  //   permissionGranted = await location.requestPermission();
  //   if (permissionGranted != PermissionStatus.granted) {
  //     throw Exception('Location permission is required.');
  //   }
  // }

  if (!headless) {
    loc.Location location = loc.Location();

    // bool serviceEnabled;

    locationData = await location.getLocation();
    return LatLong(
      locationData.latitude,
      locationData.longitude,
      locationData.accuracy,
    );
  } else {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      timeLimit: const Duration(seconds: 30),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Petrol Finder',
        notificationText: 'Getting current location for nearby fuel stations',
        enableWakeLock: false,
      ),
    );

    try {
      Stream<Position> positionStream = Geolocator.getPositionStream(
        locationSettings: settings,
      );
      Position locationData = await positionStream.first.timeout(
        const Duration(seconds: 30),
      );
      // print(
      //   'Current position obtained: ${locationData.latitude}, ${locationData.longitude}',
      // );
      return LatLong(
        locationData.latitude,
        locationData.longitude,
        locationData.accuracy,
      );
    } catch (e) {
      throw Exception('Unable to obtain a current GPS position.');
    }
  }
}
