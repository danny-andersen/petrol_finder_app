import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';

import 'package:petrol_finder_app/common.dart';
import 'package:petrol_finder_app/creds.dart';
import 'package:petrol_finder_app/location.dart';
import 'package:petrol_finder_app/fuel_finder.dart';

class PfsController extends ChangeNotifier {
  Status state;
  PfsController(this.state);

  Future<void> load() async {
    try {
      final String jsonString = await rootBundle.loadString(credentialsAsset);
      state.fuelFinderCredentials = FuelFinderCredentials.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );
      state.tokenManager = FuelFinderTokenManager(state.fuelFinderCredentials!);
    } catch (e) {
      state.status = 'Fuel Finder credentials unavailable: $e';
    }
    state.cache ??= await CacheStore().load();
  }

  Future<void> sync() async {
    if (state.lastSync != null &&
        DateTime.now().difference(state.lastSync!).inMinutes < 15) {
      state.status =
          'Last sync was ${state.lastSync!.toLocal().toString().substring(0, 16)}';
      return;
    }
    try {
      final tokenManager = state.tokenManager;
      if (tokenManager == null) {
        throw Exception(
          'Fuel Finder credentials are not configured in $credentialsAsset',
        );
      }
      final api = FuelFinderApi(tokenManager);
      final next = state.cache == null
          ? await api.fullSync()
          : await api.incrementalSync(state.cache!);
      await CacheStore().save(next);
      state.cache = next;
      state.lastSync = DateTime.now();
      state.status =
          'Data updated ${state.lastSync!.toLocal().toString().substring(0, 16)}';
    } catch (e) {
      state.status = 'Data Update failed: $e';
    }
  }

  Future<void> find() async {
    state.nearbyResults.clear();
    state.stationsInRange = 0;
    List<String> stationIdsInRange = [];

    final stations = List<dynamic>.from(state.cache?['stations'] ?? const []);

    for (double rad = 2.0; rad <= state.radius; rad += 1.0) {
      state.status =
          'Scanning ${stations.length} stations • ${state.stationsInRange} in range (radius ${rad.toStringAsFixed(1)} mi)';
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
                state.pos!.latitude,
                state.pos!.longitude,
                s.lat!,
                s.lon!,
              ) /
              1609.344;
          if (straight <= rad) {
            final matching = s.fuelPrices.where(
              (x) => x['fuel_type'] == state.fuel.type,
            );
            final price = matching.isEmpty ? null : matching.first;
            if (price != null && price['price'] is num) {
              final priceL = (price['price'] as num).toDouble();
              state.nearbyResults.add({
                'pfs': s,
                'straight': straight,
                'price': priceL,
                'fill': state.tank * priceL / 100.0,
                'open': isOpen(s.opening, DateTime.now()),
                'age': ageText(price['price_last_updated']),
                'distanceMeters': null,
                'duration': null,
                'driveCost': 0.0,
              });
              stationIdsInRange.add(s.id);
              state.nearbyResults.sort(
                (a, b) =>
                    (a['price'] as double).compareTo(b['price'] as double),
              );
            }
          }
        }
      }
      if (state.nearbyResults.length >= 10) break;
    }

    sort();
    state.status =
        'Routes for ${state.nearbyResults.length} stations found in ${state.radius} miles';
  }

  void sort() {
    switch (state.sortType) {
      case SortType.price:
        state.nearbyResults.sort(
          (a, b) => (a['price'] as double).compareTo(b['price'] as double),
        );
        break;
      case SortType.distance:
        state.nearbyResults.sort(
          (a, b) => (a['distanceMeters'] == null || b['distanceMeters'] == null)
              ? (a['straight'] as num).compareTo(b['straight'] as num)
              : (a['distanceMeters'] as num).compareTo(
                  b['distanceMeters'] as num,
                ),
        );
        break;
      case SortType.totalCost:
        state.nearbyResults.sort(
          (a, b) => ((a['fill'] as double) + (a['driveCost'] ?? 0)).compareTo(
            (b['fill'] as double) + (b['driveCost'] ?? 0),
          ),
        );
        break;
      case SortType.time:
        state.nearbyResults.sort(
          (a, b) => (a['duration'] == null || b['duration'] == null)
              ? (a['straight'] as num).compareTo(b['straight'] as num)
              : (a['duration'] as double).compareTo(b['duration'] as double),
        );
        break;
    }
  }

  double _cost(double price, double distanceMiles) {
    final litresUsed = (2 * distanceMiles) / state.mpg * 4.54609;
    return litresUsed * price / 100.0;
  }

  Future<void> routes() async {
    try {
      String? mapsKey = state.fuelFinderCredentials?.googleMapsApiKey;
      if (state.pos == null || mapsKey == null || mapsKey.isEmpty) return;
      final svc = RouteService(mapsKey);
      for (final r in state.nearbyResults) {
        final s = r['pfs'] as Pfs;
        final x = await svc.route(
          state.pos!.latitude,
          state.pos!.longitude,
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
        await Future<void>.delayed(Duration.zero);
      }
    } catch (e) {
      state.status = 'Error calculating routes, sorted by price only: $e';
    }
  }

  // Future<void> refresh() async {
  //   results = await repo.fetchNearby();
  //   notifyListeners();
  // }

  // void navigateTo(PfsResult p) {
  //   navService.navigateTo(p);
  // }
}
