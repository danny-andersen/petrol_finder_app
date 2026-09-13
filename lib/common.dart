import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:petrol_finder_app/creds.dart';

const fuelApi = 'https://www.fuel-finder.service.gov.uk/api/v1';
const fuelTokenEndpoint = '$fuelApi/oauth/generate_access_token';
const credentialsAsset = 'assets/config/fuel_finder_credentials.json';
const maxRadiusMiles = 10.0;
const defaultFuel = FuelType.petrol;
const defaultMpg = 65.0;
const defaultTankLitres = 30.0;

enum FuelType { petrol, petrolPremium, diesel, dieselPremium, electric }

extension FuelTypeLabel on FuelType {
  String get label {
    switch (this) {
      case FuelType.petrol:
        return 'Petrol (E10)';
      case FuelType.petrolPremium:
        return 'Petrol Premium (E5)';
      case FuelType.diesel:
        return 'Diesel (B7_STANDARD)';
      case FuelType.dieselPremium:
        return 'Diesel Premium (B7_PREMIUM)';
      case FuelType.electric:
        return 'Electric';
    }
  }

  String get type {
    switch (this) {
      case FuelType.petrol:
        return 'E10';
      case FuelType.petrolPremium:
        return 'E5';
      case FuelType.diesel:
        return 'B7_STANDARD';
      case FuelType.dieselPremium:
        return 'B7_PREMIUM';
      case FuelType.electric:
        return 'Electric';
    }
  }
}

enum SortType { price, totalCost, distance, time }

extension SortTypeLabel on SortType {
  String get label {
    switch (this) {
      case SortType.price:
        return 'Fuel Price / L';
      case SortType.totalCost:
        return 'Total Fill up price (inc drive costs)';
      case SortType.distance:
        return 'Distance to Fuel Station (straight line or routed)';
      case SortType.time:
        return 'Time taken to drive to Fuel Station (if avail)';
    }
  }
}

class Status {
  Map<String, dynamic>? cache;
  FuelFinderTokenManager? tokenManager;
  FuelFinderCredentials? fuelFinderCredentials;

  LatLong? pos;
  FuelType fuel = defaultFuel;
  double radius = maxRadiusMiles, mpg = defaultMpg, tank = defaultTankLitres;
  bool busy = false;
  bool finding = false;
  bool calcRoutes = false;
  String status = 'Starting…';
  DateTime? lastSync;
  final List<Map<String, dynamic>> nearbyResults = [];
  int stationsInRange = 0;
  SortType sortType = SortType.totalCost;
}

class Pfs {
  final Map<String, dynamic> raw;
  Map<String, dynamic> prices;
  Pfs(this.raw, {Map<String, dynamic>? prices}) : prices = prices ?? {};
  String get id => raw['node_id'] as String? ?? '';
  String get name => raw['trading_name'] as String? ?? 'Unnamed PFS';
  double? get lat => (raw['location']?['latitude'] as num?)?.toDouble();
  double? get lon => (raw['location']?['longitude'] as num?)?.toDouble();
  List<String> get fuelTypes =>
      List<String>.from(raw['fuel_types'] ?? const []);
  List<Map<String, dynamic>> get fuelPrices =>
      List<Map<String, dynamic>>.from(raw['fuel_prices'] ?? const {});
  Map<String, dynamic> get opening =>
      Map<String, dynamic>.from(raw['opening_times'] ?? {});
  Map<String, dynamic> toJson() => {...raw, 'fuel_prices': prices};
}

class CacheStore {
  static const fileName = 'pfs_cache.json';
  Future<File> file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<Map<String, dynamic>?> load() async {
    final f = await file();
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> cache) async {
    final f = await file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(cache), flush: true);
    await tmp.rename(f.path);
  }
}

class LatLong {
  final double latitude; // Latitude, in degrees
  final double longitude; // Longitude, in degrees
  final double?
  accuracy; // Estimated horizontal accuracy of this location, radial, in meters
  LatLong(this.latitude, this.longitude, this.accuracy);
}

String formatDate(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}

bool isOpen(Map<String, dynamic> opening, DateTime now) {
  final days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final day = days[now.weekday - 1];
  final d = opening['usual_days']?[day];
  if (d == null) return false;
  if (d['is_24_hours'] == true) return true;
  final o = d['open'] as String?;
  final c = d['close'] as String?;
  if (o == null || c == null || o == c) return false;
  final t = now.hour * 60 + now.minute;
  int mins(String s) {
    final x = s.split(':');
    return int.parse(x[0]) * 60 + int.parse(x[1]);
  }

  final a = mins(o), b = mins(c);
  return a < b ? t >= a && t < b : t >= a || t < b;
}

String ageText(String? iso) {
  if (iso == null) return 'unknown';
  final d = DateTime.tryParse(iso);
  if (d == null) return 'unknown';
  final days = DateTime.now().toUtc().difference(d.toUtc()).inHours / 24;
  if (days < 1) return '${(days * 24).round()}h';
  return '${days.toStringAsFixed(1)}d';
}
