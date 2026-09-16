import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:petrol_finder_app/common.dart';
import 'package:petrol_finder_app/creds.dart';
import 'package:petrol_finder_app/location.dart';
import 'package:petrol_finder_app/detail_screen.dart';
import 'package:petrol_finder_app/controller.dart';
import 'package:petrol_finder_app/car_play.dart';

final AndroidAutoController _androidAutoController = AndroidAutoController(
  Status(),
);
final Status appState = _androidAutoController.state;

// late AndroidAutoController _androidAutoController;
final PfsController _pfsController = PfsController(appState);

void main() async {
  // 1. Force the binary messenger to bind native Android service threads
  WidgetsFlutterBinding.ensureInitialized();
  _androidAutoController.pfsController = _pfsController;
  _androidAutoController.init();

  runApp(const PetrolFinderApp());
}

// void main() {
//   // Ensures native platform channels are safely bound before executing code
//   WidgetsFlutterBinding.ensureInitialized();
//   AndroidAutoController.setInitialCarplayRootTemplate();
//   runApp(const PetrolFinderApp());
// }

class PetrolFinderApp extends StatefulWidget {
  const PetrolFinderApp({super.key});
  @override
  State<PetrolFinderApp> createState() => _AppState();
}

class _AppState extends State<PetrolFinderApp> with WidgetsBindingObserver {
  bool _phoneInitialised = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _initialisePhoneApp();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initialisePhoneApp();
    }
  }

  void _initialisePhoneApp() async {
    if (_phoneInitialised) return;
    await _load(context);
    await _syncAndFind(context, false);
    _phoneInitialised = true;
  }

  @override
  void dispose() {
    _androidAutoController.dispose();
    super.dispose();
  }

  Future<void> _load(BuildContext context) async {
    try {
      if (context.mounted) {
        final raw = await DefaultAssetBundle.of(context)
            .loadString(credentialsAsset);
        appState.fuelFinderCredentials = FuelFinderCredentials.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        appState.tokenManager = FuelFinderTokenManager(
          appState.fuelFinderCredentials!,
        );
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          appState.status = 'Fuel Finder credentials unavailable: $e';
        });
      }
    }
    if (context.mounted) {
      setState(() {
        appState.status = 'Loading cache data…';
      });
    }
    appState.cache = await CacheStore().load();
  }

  Future<void> _syncAndFind(BuildContext context, bool headless) async {
    // try {
    if (context.mounted) {
      setState(() {
        appState.status = 'Checking for updates to fuel station data…';
      });
    }
    await _pfsController.sync();
    if (context.mounted) {
      setState(() {
        appState.status = 'Waiting for GPS...';
      });
    }
    appState.pos = await currentPosition(headless);
    if (context.mounted) {
      setState(() {
        appState.status = 'Finding nearby stations...';
      });
    }
    await _findAndRoute(context);
    // } catch (e) {
    //  appState.busy = false;
    //   appState.finding = false;
    //   appState.calcRoutes = false;
    //   if (context.mounted) {
    //     setState(() {});
    //     if (e.toString().contains('Routes API 429')) {
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         SnackBar(
    //           content: Text(
    //             '${appState.status}: Maps Routes API request failed (429). This is likely due to exceeding the free quota. Please check your Google Cloud Console for usage and billing.',
    //           ),
    //         ),
    //       );
    //     } else {
    //       ScaffoldMessenger.of(context)
    //           .showSnackBar(SnackBar(content: Text('${appState.status}: $e')));
    //     }
    //   }
    // }
  }

  Future<void> _findAndRoute(BuildContext context) async {
    await _pfsController.find();
    if (context.mounted) {
      setState(() {});
    }
    // Calculate road routes.
    await _pfsController.routes();
    _pfsController.sort();
    if (context.mounted) {
      setState(() {});
    }
    _androidAutoController.updateAndroidAutoResults();
  }

  Future<void> _settings(BuildContext context) async {
    final r = TextEditingController(text: '${appState.radius} miles'),
        m = TextEditingController(text: '${appState.mpg}'),
        t = TextEditingController(text: '${appState.tank}');
    FuelType selectedFuel = appState.fuel;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Settings'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              Text(
                "Fuel Type",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              StatefulBuilder(
                builder: (context, setState) {
                  return RadioGroup<FuelType>(
                    groupValue: selectedFuel,
                    onChanged: (value) {
                      setState(() => selectedFuel = value!);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: FuelType.values.map((ft) {
                        return RadioListTile<FuelType>(
                          value: ft,
                          title: Text(ft.label),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              TextField(
                controller: r,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Search radius (miles)',
                ),
              ),
              TextField(
                controller: m,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Vehicle MPG'),
              ),
              TextField(
                controller: t,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tank size (litres)',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                appState.cache == null || appState.cache!['stations'] == null
                    ? 'No fuel stations loaded'
                    : '${(appState.cache!['stations'] as List).length} fuel stations loaded',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              appState.fuel = selectedFuel;
              appState.radius = double.tryParse(r.text) ?? appState.radius;
              appState.mpg = double.tryParse(m.text) ?? appState.mpg;
              appState.tank = double.tryParse(t.text) ?? appState.tank;

              await _findAndRoute(context);
              if (mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseSort(BuildContext context) async {
    final selected = await showDialog<SortType>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sort by'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => RadioGroup<SortType>(
            groupValue: appState.sortType,
            onChanged: (value) {
              if (value != null) {
                setDialogState(() {});
                Navigator.pop(context, value);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: SortType.values
                  .map(
                    (type) => RadioListTile<SortType>(
                      title: Text(type.label),
                      value: type,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
    if (selected != null && context.mounted) {
      setState(() {
        appState.sortType = selected;
        _pfsController.sort();
      });
    }
    _androidAutoController.updateAndroidAutoResults();
  }

  @override
  Widget build(BuildContext context) {
    // final rs = results();
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Petrol Finder'),
          actions: [
            Builder(
              builder: (innerContext) => IconButton(
                tooltip: 'Sort by',
                onPressed: () => appState.nearbyResults.isEmpty
                    ? null
                    : _chooseSort(innerContext),
                icon: const Icon(Icons.sort),
              ),
            ),
            Builder(
              builder: (innerContext) => IconButton(
                onPressed: () {
                  _syncAndFind(innerContext, false);
                },
                icon: const Icon(Icons.sync),
              ),
            ),
            Builder(
              builder: (innerContext) => IconButton(
                onPressed: () => _settings(innerContext),
                icon: const Icon(Icons.settings),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            ListTile(title: Text(appState.status)),
            if (appState.pos == null)
              Expanded(child: Center(child: Text(appState.status)))
            else if (appState.nearbyResults.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    appState.finding ? 'Scanning the cached stations…' : 'No stations in range with a price for the selected fuel.',
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: appState.nearbyResults.length,
                  itemBuilder: (ctx, i) {
                    final x = appState.nearbyResults[i];
                    final p = x['pfs'] as Pfs;
                    final routeMiles = x['distanceMeters'] == null
                        ? null
                        : (x['distanceMeters'] as num) / 1609.344;
                    final borderColor = x['open']
                        ? _ageColor(x['age'])
                        : Colors.red;
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: borderColor, width: 6),
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _openDetails(ctx, x),
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 12,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // --- Title row ---
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.navigation),
                                      onPressed: () => _navigate(p),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 2),

                                // --- Distance / Duration / Status ---
                                Row(
                                  children: [
                                    Text(
                                      '${routeMiles?.toStringAsFixed(1) ?? x["straight"].toStringAsFixed(1)} mi',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      x['duration'] != null
                                          ? '${x['duration'].toStringAsFixed(1)} mins'
                                          : '(No route…)',
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      x['open'] ? 'OPEN' : 'CLOSED',
                                      style: TextStyle(
                                        color: x['open']
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),

                                // const SizedBox(height: 4),

                                // --- Fuel section ---
                                Row(
                                  children: [
                                    Text(
                                      '${appState.fuel.label}: ${(x["price"] as double).toStringAsFixed(1)}p/L',
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${x["age"]} ago',
                                      style: TextStyle(
                                        color: _ageColor(x['age']),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Total Fillup cost £${((x["fill"] as double) + (x['driveCost'] ?? 0)).toStringAsFixed(2)} ',
                                ),

                                const SizedBox(height: 8),

                                // --- Age ---
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _ageInDays(String age) {
    final value = double.tryParse(age.substring(0, age.length - 1)) ?? 0;
    final unit = age[age.length - 1];

    if (unit == 'd') return value; // already in days
    if (unit == 'h') return value / 24.0; // convert hours → days

    return 0; // fallback
  }

  Color _ageColor(String age) {
    final double days = _ageInDays(age);
    if (days > 10) return Colors.red; // old → red
    if (days < 5) return Colors.green; // fresh → green
    return Colors.yellow.shade900; // mid → yellow
  }

  Future<void> _openDetails(
    BuildContext context,
    Map<String, dynamic> x,
  ) async {
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(data: x)),
    );
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
}
