import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

const fuelApi = 'https://www.fuel-finder.service.gov.uk/api/v1';
const fuelTokenEndpoint = '$fuelApi/oauth/generate_access_token';
const credentialsAsset = 'assets/config/fuel_finder_credentials.json';
const maxRadiusMiles = 10.0;
const defaultFuel = 'E10';
const defaultMpg = 65.0;
const defaultTankLitres = 35.0;

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
