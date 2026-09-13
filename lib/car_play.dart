import 'package:url_launcher/url_launcher.dart';

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

  void init() {
    // setupCarBootstrap();
    _androidAuto.addListenerOnConnectionChange(_onAndroidAutoConnectionChange);
    print('Android Auto connection listener added');
    updateAndroidAutoResults();
  }

  void _onAndroidAutoConnectionChange(ConnectionStatusTypes connected) {
    print('Android Auto connection status: $_androidAutoConnected');
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

  void setupCarBootstrap() {
    channel.setMethodCallHandler((call) async {
      if (call.method == "carStart") {
        print("Car app started");
        await _autoFind();
      }
    });
  }

  void dispose() {
    _androidAuto.removeListenerOnConnectionChange();
  }

  Future<void> _autoFind() async {
    // try {
    state.status = 'Checking for updates to fuel station data…';
    updateAndroidAutoResults();
    await pfsController!.sync();
    state.status = 'Waiting for GPS...';
    updateAndroidAutoResults();
    print("Calling currentPosition() for Android Auto with headless mode");
    state.pos = await currentPosition(true);
    state.status = 'Finding nearby stations...';
    updateAndroidAutoResults();
    await pfsController!.find();
    updateAndroidAutoResults();
    // Calculate road routes.
    await pfsController!.routes();
    pfsController!.sort();
    updateAndroidAutoResults();
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
    final uri = Uri.parse('google.navigation:q=${p.lat},${p.lon}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final web = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lon}',
      );
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

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
    // if (!_androidAutoConnected) return;

    final snapshot = List<Map<String, dynamic>>.from(state.nearbyResults);
    final items = <AAListItem>[];

    if (snapshot.isEmpty) {
      print('No nearby stations found, showing status: ${state.status}');
      items.add(
        AAListItem(
          title: 'No nearby stations found, please wait...',
          // subtitle: _finding ? status : 'Use GPS on the phone to find stations',
        ),
      );
    } else {
      for (final x in snapshot.take(20)) {
        final p = x['pfs'] as Pfs;
        final price = (x['price'] as num).toDouble();
        final distance = x['distanceMeters'] == null
            ? '${(x['straight'] as num).toDouble().toStringAsFixed(1)} mi'
            : '${((x['distanceMeters'] as num).toDouble() / 1609.344).toStringAsFixed(1)} mi';
        final total =
            (x['fill'] as num).toDouble() +
            ((x['driveCost'] ?? 0) as num).toDouble();
        final subtitle =
            '${state.fuel.label} ${price.toStringAsFixed(1)}p/L • $distance • ${_aaDuration(x)} • £${total.toStringAsFixed(2)}';

        items.add(
          AAListItem(
            title: p.name,
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
      print(
        'Connected status: $_androidAutoConnected. Android Auto template updated with ${items.length} items',
      );
    } catch (e) {
      // Android Auto may disconnect while the phone UI is updating.
      print('Failed to update Android Auto template: $e');
    }
  }
}
