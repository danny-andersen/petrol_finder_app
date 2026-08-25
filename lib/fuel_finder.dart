import 'dart:math' as math;
import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:petrol_finder_app/common.dart';
import 'package:petrol_finder_app/creds.dart';

class FuelFinderApi {
  final FuelFinderTokenManager tokenManager;
  FuelFinderApi(this.tokenManager);

  static String _bodyPreview(String body) =>
      body.substring(0, math.min(300, body.length));

  Future<http.Response> _get(Uri uri, {bool retried = false}) async {
    final token = await tokenManager.getAccessToken(forceRefresh: retried);
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 401 && !retried) {
      tokenManager.invalidate();
      return _get(uri, retried: true);
    }
    return response;
  }

  Future<List<dynamic>> _paged(String path, {String? since}) async {
    final all = <dynamic>[];
    for (var batch = 1; ; batch++) {
      final q = <String, String>{'batch-number': '$batch'};
      if (since != null) q['effective-start-timestamp'] = since;
      final uri = Uri.parse('$fuelApi$path').replace(queryParameters: q);
      final r = await _get(uri);
      final data = jsonDecode(r.body);
      //Check whether batch is complete
      if (r.statusCode == 404) {
        final String msg = data['data']['data']['message'];
        if (msg.contains('not available')) {
          break;
        }
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw HttpException(
          'Fuel Finder HTTP ${r.statusCode}: ${_bodyPreview(r.body)}',
        );
      }
      if (data is! List || data.isEmpty) break;
      all.addAll(data);
    }
    return all;
  }

  Future<Map<String, dynamic>> fullSync() async {
    final pfs = await _paged('/pfs');
    final prices = await _paged('/pfs/fuel-prices');
    return _merge(pfs, prices, DateTime.now().toUtc());
  }

  Future<Map<String, dynamic>> incrementalSync(
    Map<String, dynamic> cache,
  ) async {
    final last = cache['last_sync_utc'] as String?;
    if (last == null) return fullSync();
    final pfs = await _paged('/pfs', since: _apiTimestamp(last));
    final prices = await _paged('/pfs/fuel-prices', since: _apiTimestamp(last));
    final existing = List<dynamic>.from(cache['stations'] ?? []);
    final byId = <String, Map<String, dynamic>>{
      for (final x in existing)
        (x['node_id'] as String): Map<String, dynamic>.from(x),
    };
    for (final x in pfs) {
      byId[x['node_id']] = Map<String, dynamic>.from(x);
    }
    for (final x in prices) {
      final id = x['node_id'];
      final station = byId[id];
      if (station == null) continue;
      final current = <dynamic>[];
      current.addAll(station['fuel_prices'] ?? const []);
      final incoming = List<dynamic>.from(x['fuel_prices'] ?? const []);
      final priceByFuel = <String, Map<String, dynamic>>{
        for (final p in current) p['fuel_type']: Map<String, dynamic>.from(p),
      };
      for (final p in incoming) {
        final fuel = p['fuel_type'];
        final old = priceByFuel[fuel];
        final newTs = DateTime.tryParse(
          p['price_change_effective_timestamp'] ??
              p['price_last_updated'] ??
              '',
        );
        final oldTs = DateTime.tryParse(
          old?['price_change_effective_timestamp'] ??
              old?['price_last_updated'] ??
              '',
        );
        if (old == null ||
            (newTs != null && (oldTs == null || newTs.isAfter(oldTs)))) {
          priceByFuel[fuel] = Map<String, dynamic>.from(p);
        }
      }
      station['fuel_prices'] = priceByFuel.values.toList();
    }
    return {
      'schema': 1,
      'last_sync_utc': DateTime.now().toUtc().toIso8601String(),
      'stations': byId.values.toList(),
    };
  }

  String _apiTimestamp(String iso) {
    final d = DateTime.parse(iso).toUtc();
    return d.toIso8601String().replaceFirst('T', ' ').split('.').first;
  }

  Map<String, dynamic> _merge(
    List<dynamic> pfs,
    List<dynamic> prices,
    DateTime now,
  ) {
    final byId = <String, Map<String, dynamic>>{
      for (final x in pfs)
        (x['node_id'] as String): Map<String, dynamic>.from(x),
    };
    for (final x in prices) {
      final s = byId[x['node_id']];
      if (s != null) s['fuel_prices'] = x['fuel_prices'] ?? [];
    }
    return {
      'schema': 1,
      'last_sync_utc': now.toIso8601String(),
      'stations': byId.values.toList(),
    };
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
