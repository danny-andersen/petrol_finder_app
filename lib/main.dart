import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import 'package:petrol_finder_app/common.dart';
import 'package:petrol_finder_app/creds.dart';
import 'package:petrol_finder_app/fuel_finder.dart';
import 'package:petrol_finder_app/location.dart';
import 'package:petrol_finder_app/detail_screen.dart';

void main() {
  // Ensures native platform channels are safely bound before executing code
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PetrolFinderApp());
}

class PetrolFinderApp extends StatefulWidget {
  const PetrolFinderApp({super.key});
  @override
  State<PetrolFinderApp> createState() => _AppState();
}

class _AppState extends State<PetrolFinderApp> {
  Map<String, dynamic>? cache;
  FuelFinderTokenManager? _tokenManager;
  FuelFinderCredentials? _fuelFinderCredentials;
  LatLong? pos;
  String fuel = defaultFuel;
  double radius = maxRadiusMiles, mpg = defaultMpg, tank = defaultTankLitres;
  bool busy = false;
  bool _finding = false;
  String status = 'Starting…';
  DateTime? lastSync;
  final List<Map<String, dynamic>> _nearbyResults = [];
  int _stationsInRange = 0;

  @override
  void initState() {
    super.initState();
    _load(context);
  }

  Future<void> _load(BuildContext context) async {
    final sp = await SharedPreferences.getInstance();
    try {
      if (context.mounted) {
        final raw = await DefaultAssetBundle.of(context)
            .loadString(credentialsAsset);
        _fuelFinderCredentials = FuelFinderCredentials.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        _tokenManager = FuelFinderTokenManager(_fuelFinderCredentials!);
      }
    } catch (e) {
      status = 'Fuel Finder credentials unavailable: $e';
    }
    fuel = sp.getString('fuel_type') ?? defaultFuel;
    radius = sp.getDouble('radius_miles') ?? maxRadiusMiles;
    mpg = sp.getDouble('mpg') ?? defaultMpg;
    tank = sp.getDouble('tank_litres') ?? defaultTankLitres;
    cache = await CacheStore().load();
    pos = await currentPosition();
    if (context.mounted) {
      setState(() {});
      await _sync(context);
    }
  }

  Future<void> _sync(BuildContext context) async {
    if (busy) return;
    if (lastSync != null &&
        DateTime.now().difference(lastSync!).inMinutes < 15) {
      status =
          'Last sync was ${lastSync!.toLocal().toString().substring(0, 16)}';
      if (context.mounted) setState(() {});
      return;
    }
    setState(() => busy = true);
    try {
      status = 'Updating fuel station data…';
      final tokenManager = _tokenManager;
      if (tokenManager == null) {
        throw Exception(
          'Fuel Finder credentials are not configured in $credentialsAsset',
        );
      }
      final api = FuelFinderApi(tokenManager);
      final next = cache == null
          ? await api.fullSync()
          : await api.incrementalSync(cache!);
      await CacheStore().save(next);
      cache = next;
      lastSync = DateTime.now();
      status =
          'Data updated ${lastSync!.toLocal().toString().substring(0, 16)}';
    } catch (e) {
      status = 'Update failed: $e';
    } finally {
      if (context.mounted) setState(() => busy = false);
    }
  }

  Future<void> _find(BuildContext context) async {
    try {
      pos = await currentPosition();
      if (!context.mounted) return;
      setState(() {
        _nearbyResults.clear();
        _stationsInRange = 0;
        _finding = true;
        status = 'Scanning cached stations…';
      });
      List<String> stationIdsInRange = [];

      final stations = List<dynamic>.from(cache?['stations'] ?? const []);
      // final started = DateTime.now();
      DateTime lastPaint = DateTime.now();

      for (double rad = 2.0; rad <= radius; rad += 1.0) {
        if (!context.mounted) return;
        setState(() {
          status =
              'Scanning ${stations.length} stations • $_stationsInRange in range (radius ${rad.toStringAsFixed(1)} mi)';
        });
        await Future<void>.delayed(Duration.zero);
        for (final raw in stations) {
          final s = Pfs(Map<String, dynamic>.from(raw));
          //Only consider stations that have a price for the selected fuel type, and are not already in the results list.
          if (!stationIdsInRange.contains(s.id) &&
              s.lat != null &&
              s.lon != null &&
              s.fuelPrices.isNotEmpty) {
            final straight =
                Geolocator.distanceBetween(
                  pos!.latitude,
                  pos!.longitude,
                  s.lat!,
                  s.lon!,
                ) /
                1609.344;
            if (straight <= rad) {
              final matching = s.fuelPrices.where(
                (x) => x['fuel_type'] == fuel,
              );
              final price = matching.isEmpty ? null : matching.first;
              if (price != null && price['price'] is num) {
                final priceL = (price['price'] as num).toDouble();
                setState(() {
                  _nearbyResults.add({
                    'pfs': s,
                    'straight': straight,
                    'price': priceL,
                    'fill': tank * priceL / 100.0,
                    'open': isOpen(s.opening, DateTime.now()),
                    'age': ageText(price['price_last_updated']),
                    'distanceMeters': null,
                    'duration': null,
                    'driveCost': 0.0,
                  });
                  stationIdsInRange.add(s.id);
                  _nearbyResults.sort(
                    (a, b) =>
                        (a['price'] as double).compareTo(b['price'] as double),
                  );
                });
              }
            }
          }
        }
        if (_nearbyResults.length >= 10) break;

        // Paint frequently enough for a live result stream without rebuilding
        // the UI for every single station in a large national cache.
        if (DateTime.now().difference(lastPaint).inMilliseconds >= 80) {
          lastPaint = DateTime.now();
          if (context.mounted) {
            setState(() {
              status =
                  'Scanning ${stations.length} stations • $_stationsInRange in range';
            });
          }
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (context.mounted) {
        setState(() {
          _finding = false;
          status = '${_nearbyResults.length} stations found in $radius miles';
        });
      }

      // Calculate road routes.
      await _routes(context, _nearbyResults);

      //Further sort

      // final c = Map<String, dynamic>.from(cache ?? {});
      // c['current_location'] = {
      //   'latitude': pos!.latitude,
      //   'longitude': pos!.longitude,
      // };
      // c['settings'] = {
      //   'fuel_type': fuel,
      //   'radius_miles': radius,
      //   'mpg': mpg,
      //   'tank_litres': tank,
      // };
      // c['nearby_results'] = _nearbyResults.take(10).map((x) {
      //   final p = x['pfs'] as Pfs;
      //   return {
      //     'node_id': p.id,
      //     'price': x['price'],
      //     'distanceMeters': x['distanceMeters'],
      //     'duration': x['duration'],
      //     'fill': x['fill'],
      //     'driveCost': x['driveCost'] ?? 0,
      //     'totalCost': (x['fill'] as double) + (x['driveCost'] ?? 0),
      //   };
      // }).toList();
      // cache = c;
      // await CacheStore().save(c);
    } catch (e) {
      _finding = false;
      if (context.mounted) {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  double _cost(double price, double distanceMiles) {
    final litresUsed = (2 * distanceMiles) / mpg * 4.54609;
    return litresUsed * price / 100.0;
  }

  Future<void> _routes(
    BuildContext context,
    List<Map<String, dynamic>> rs,
  ) async {
    String? mapsKey = _fuelFinderCredentials?.googleMapsApiKey;
    if (pos == null || mapsKey == null || mapsKey.isEmpty) return;
    final svc = RouteService(mapsKey);
    for (final r in rs.take(5)) {
      final s = r['pfs'] as Pfs;
      try {
        final x = await svc.route(
          pos!.latitude,
          pos!.longitude,
          s.lat!,
          s.lon!,
        );
        String duration = x['duration'];
        r['distanceMeters'] = x['distanceMeters'];
        r['duration'] =
            double.parse(duration.substring(0, duration.length - 1)) / 60.0;
        r['driveCost'] = _cost(
          r['price'] as double,
          (x['distanceMeters'] as num).toDouble() / 1609.344,
        );
      } catch (e) {
        if (context.mounted) {
          setState(() {});
          if (e.toString().contains('Routes API 429')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Google Maps Routes API request failed (429). This is likely due to exceeding the free quota. Please check your Google Cloud Console for usage and billing.',
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$e')));
          }
        }
      }
    }
    rs.sort(
      (a, b) => ((a['fill'] as double) + (a['driveCost'] ?? 0)).compareTo(
        (b['fill'] as double) + (b['driveCost'] ?? 0),
      ),
    );
    if (context.mounted) setState(() {});
  }

  Future<void> _settings(BuildContext context) async {
    final f = TextEditingController(text: fuel),
        r = TextEditingController(text: '$radius'),
        m = TextEditingController(text: '$mpg'),
        t = TextEditingController(text: '$tank');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Settings'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: f,
                decoration: const InputDecoration(
                  labelText: 'Fuel type (E10, E5, B7_STANDARD…)',
                ),
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
              final sp = await SharedPreferences.getInstance();
              await sp.setString('fuel_type', f.text.trim());
              await sp.setDouble(
                'radius_miles',
                double.tryParse(r.text) ?? radius,
              );
              await sp.setDouble('mpg', double.tryParse(m.text) ?? mpg);
              await sp.setDouble(
                'tank_litres',
                double.tryParse(t.text) ?? tank,
              );
              fuel = f.text.trim();
              radius = double.tryParse(r.text) ?? radius;
              mpg = double.tryParse(m.text) ?? mpg;
              tank = double.tryParse(t.text) ?? tank;
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
                onPressed: () => _settings(innerContext),
                icon: const Icon(Icons.settings),
              ),
            ),
            Builder(
              builder: (innerContext) => IconButton(
                onPressed: () {
                  _sync(innerContext);
                  _find(innerContext);
                },
                icon: const Icon(Icons.sync),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            ListTile(
              title: Text(status),
              subtitle: Text(
                cache == null || cache!['stations'] == null
                    ? 'No local station cache'
                    : '${(cache!['stations'] as List).length} stations cached',
              ),
            ),
            if (pos == null)
              const Expanded(child: Center(child: Text('Waiting for GPS…')))
            else if (_nearbyResults.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _finding ? 'Scanning the cached stations…' : 'No stations in range with a price for the selected fuel.',
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _nearbyResults.length,
                  itemBuilder: (ctx, i) {
                    final x = _nearbyResults[i];
                    final p = x['pfs'] as Pfs;
                    final routeMiles = x['distanceMeters'] == null
                        ? null
                        : (x['distanceMeters'] as num) / 1609.344;
                    final drive = x['driveCost'] ?? 0.0;
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
                                      '$fuel: ${(x["price"] as double).toStringAsFixed(1)}p/L',
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Fillup £${(x["fill"] as double).toStringAsFixed(2)}',
                                    ),
                                    x['duration'] != null
                                        ? Text(
                                            'round-trip £${drive.toStringAsFixed(2)}',
                                          )
                                        : const SizedBox(width: 0),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // --- Age ---
                                Text(
                                  '${x["age"]} ago',
                                  style: TextStyle(color: _ageColor(x['age'])),
                                ),
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
