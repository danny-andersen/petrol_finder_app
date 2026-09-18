import 'package:flutter/services.dart';
import 'package:flutter_carplay/flutter_carplay.dart';

import 'package:petrol_finder_app/common.dart';
import 'package:petrol_finder_app/location.dart';
import 'package:petrol_finder_app/controller.dart';

const channel = MethodChannel("car_bootstrap");

class AndroidAutoController {
  final FlutterAndroidAuto _androidAuto = FlutterAndroidAuto();
  Status state;
  PfsController? pfsController;
  AndroidAutoController(this.state);

  ConnectionStatusTypes _androidAutoConnected =
      ConnectionStatusTypes.disconnected;

  void init() async {
    // setupCarBootstrap();
    _androidAuto.addListenerOnConnectionChange(_onAndroidAutoConnectionChange);
    // print('Android Auto connection listener added');
    checkAndroidAutoConnection();
    state.cache = await CacheStore().load();
    await _autoFind();
    // updateAndroidAutoResults();
  }

  void checkAndroidAutoConnection() {
    _androidAutoConnected =
        FlutterAndroidAuto.connectionStatus ==
            ConnectionStatusTypes.connected.name
        ? ConnectionStatusTypes.connected
        : ConnectionStatusTypes.disconnected;
  }

  void _onAndroidAutoConnectionChange(ConnectionStatusTypes connected) {
    // print('Android Auto connection status: $_androidAutoConnected');
    if (_androidAutoConnected != connected &&
        connected == ConnectionStatusTypes.connected) {
      _androidAutoConnected = connected;
      // if (pfsController != null) {
      //   print('Android Auto now connected, starting auto-find');
      //   _autoFind();
      // }
      updateAndroidAutoResults();
    }
  }

  void dispose() {
    _androidAuto.removeListenerOnConnectionChange();
  }

  Future<void> _autoFind() async {
    if (state.busy) return;
    state.busy = true;
    state.status = 'Checking for updates to fuel station data…';
    updateAndroidAutoResults();
    try {
      await pfsController!.sync();
      state.status = 'Waiting for GPS...';
    } catch (e) {
      state.status =
          'Note cannot refresh Petrol Station data, waiting for GPS...';
    }
    updateAndroidAutoResults();
    // print("Calling currentPosition() for Android Auto with headless mode");
    try {
      for (int i = 0; i < 3; i++) {
        try {
          state.pos = await currentPosition(true);
          break;
        } catch (e) {
          print('Attempt ${i + 1} to get GPS position failed: $e');
          if (i == 2) rethrow; // Rethrow on the last attempt
          await Future.delayed(
            const Duration(seconds: 1),
          ); // Wait before retrying
        }
      }
      state.status = 'Finding nearby stations...';
    } catch (e) {
      state.status =
          'Error getting GPS position: $e. Please check location permissions.';
      updateAndroidAutoResults();
      state.busy = false;
      return;
    }
    updateAndroidAutoResults();
    await pfsController!.find();
    updateAndroidAutoResults();
    // Calculate road routes.
    try {
      await pfsController!.routes();
    } catch (e) {
      state.status = 'Error calculating routes, sorted by price only: $e';
      updateAndroidAutoResults();
      state.busy = false;
      return;
    }
    pfsController!.sort();
    updateAndroidAutoResults();
    state.busy = false;
  }

  String _aaDuration(Map<String, dynamic> x) {
    final duration = x['duration'] != null
        ? '${x['duration'].toStringAsFixed(1)} mins'
        : '(No route…)';
    final match = RegExp(r'(\d+)s').firstMatch(duration);
    if (match == null) return duration;
    final seconds = int.tryParse(match.group(1)!) ?? 0;
    final minutes = (seconds / 60).round();
    return minutes < 1 ? '<1 min' : '$minutes min';
  }

  Future<void> _navigate(Pfs p) async {
    if (p.lat == null || p.lon == null) {
      state.status = 'No coordinates for ${p.name}, cannot navigate';
      return;
    }
    await navigateToPointOnAndroidAuto(
      latitude: p.lat!,
      longitude: p.lon!,
      label: p.name,
    );
    // AndroidAutoNavigator.startNavigation(
    //   latitude: p.lat!,
    //   longitude: p.lon!,
    //   label: p.name,
    // );
  }

  Future<void> navigateToPointOnAndroidAuto({
    required double latitude,
    required double longitude,
    String label = 'Destination',
  }) async {
    // print('Requesting native Android Auto navigation to $latitude, $longitude');

    try {
      await AndroidAutoNavigator.startNavigation(
        latitude: latitude,
        longitude: longitude,
        label: label,
      );
    } catch (e) {
      state.status = 'Could not start Android Auto navigation: $e';
    }
  }

  // void navigateToPointOnAndroidAuto({
  //   required double latitude,
  //   required double longitude,
  // }) async {
  //   // Construct the geo URI string
  //   final String geoUri = 'google.navigation:q=$latitude,$longitude';

  //   final AndroidIntent intent = AndroidIntent(
  //     action: 'android.intent.action.VIEW',
  //     data: geoUri,
  //     // Optional: explicitly target the map/car intent system if needed
  //     flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
  //   );

  //   print('Launching Android Auto navigation to $latitude, $longitude');
  //   try {
  //     await intent.launch();
  //   } catch (e) {
  //     print("Could not launch Android Auto navigation: $e");
  //   }
  // }

  static void setInitialCarplayRootTemplate() {
    final template = AAListTemplate(
      title: 'Petrol Finder App',
      sections: [
        AAListSection(
          title: "Starting up...",
          items: [AAListItem(title: 'Please wait')],
        ),
      ],
      emptyViewTitleVariants: const ['No stations'],
    );

    try {
      FlutterAndroidAuto.setRootTemplate(template: template);
    } catch (e) {
      // Android Auto may disconnect while the phone UI is updating.
      print('Failed to update Android Auto template: $e');
    }
  }

  Future<void> updateAndroidAutoResults() async {
    checkAndroidAutoConnection();
    // print(
    //   'Updating Android Auto results, connection status: $_androidAutoConnected, state: ${state.status}, nearbyResults: ${state.nearbyResults.length}',
    // );
    if (_androidAutoConnected != ConnectionStatusTypes.connected) return;

    final snapshot = List<Map<String, dynamic>>.from(state.nearbyResults);
    final items = <AAListItem>[];

    if (snapshot.isEmpty) {
      // print('No nearby stations found, showing status: ${state.status}');
      items.add(
        AAListItem(
          title: 'No nearby stations found, press to refresh...',
          onPress: (complete, self) async {
            await _autoFind();
            complete();
          },
          // subtitle: _finding ? status : 'Use GPS on the phone to find stations',
        ),
      );
    } else {
      items.add(
        AAListItem(
          title: "Press to refresh",
          onPress: (complete, self) async {
            await _autoFind();
            complete();
          },
        ),
      );
      for (final x in snapshot.take(20)) {
        final p = x['pfs'] as Pfs;
        final open = x['open'] ? 'OPEN' : 'CLOSED';

        final price = (x['price'] as num).toDouble();
        final distance = x['distanceMeters'] == null
            ? '${(x['straight'] as num).toDouble().toStringAsFixed(1)} mi'
            : '${((x['distanceMeters'] as num).toDouble() / 1609.344).toStringAsFixed(1)} mi';
        final total =
            (x['fill'] as num).toDouble() +
            ((x['driveCost'] ?? 0) as num).toDouble();
        final subtitle =
            '${state.fuel.label} ${price.toStringAsFixed(1)}p/L • $distance • ${_aaDuration(x)} • £${total.toStringAsFixed(2)} ${x["age"]} ago';

        items.add(
          AAListItem(
            title: '${p.name} ($open)',
            subtitle: subtitle,
            onPress: (complete, self) async {
              await _navigate(p);
              complete();
            },
          ),
        );
      }
    }

    final template = AAListTemplate(
      title: 'Petrol Finder ',
      sections: [AAListSection(title: state.status, items: items)],
      emptyViewTitleVariants: const ['No stations'],
    );

    try {
      await FlutterAndroidAuto.setRootTemplate(template: template);
      _androidAuto.forceUpdateRootTemplate();
      // print('${state.status}. Android Auto template ${items.length} items');
    } catch (e) {
      // Android Auto may disconnect while the phone UI is updating.
      print('Failed to update Android Auto template: $e');
    }
  }
}

class AndroidAutoNavigator {
  // Define a unique channel name
  static const MethodChannel _channel = MethodChannel(
    'com.dsa.petrol_finder_app/android_auto',
  );

  static Future<void> startNavigation({
    required double latitude,
    required double longitude,
    String label = 'Destination',
  }) async {
    try {
      await _channel.invokeMethod('startNavigation', {
        'latitude': latitude,
        'longitude': longitude,
        'label': label,
      });
    } on PlatformException catch (e) {
      print("Failed to start navigation: '${e.message}'.");
    }
  }
}

// Example usage:
// await AndroidAutoNavigator.startNavigation(latitude: 37.7749, longitude: -122.4194, label: "San Francisco");
