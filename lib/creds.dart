import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:petrol_finder_app/common.dart';

class FuelFinderCredentials {
  final String clientId;
  final String clientSecret;
  final String googleMapsApiKey;
  const FuelFinderCredentials({
    required this.clientId,
    required this.clientSecret,
    required this.googleMapsApiKey,
  });

  factory FuelFinderCredentials.fromJson(Map<String, dynamic> json) {
    final id = json['client_id'] as String?;
    final secret = json['client_secret'] as String?;
    final apiKey = json['google_maps_api_key'] as String?;
    if (id == null ||
        id.trim().isEmpty ||
        secret == null ||
        secret.trim().isEmpty ||
        apiKey == null ||
        apiKey.trim().isEmpty) {
      throw const FormatException(
        'Fuel Finder credentials asset must contain client_id and client_secret.',
      );
    }
    return FuelFinderCredentials(
      clientId: id.trim(),
      clientSecret: secret.trim(),
      googleMapsApiKey: apiKey.trim(),
    );
  }
}

class FuelFinderTokenManager {
  final FuelFinderCredentials credentials;
  String? _accessToken;
  DateTime? _expiresAt;
  Future<void>? _tokenRequest;

  FuelFinderTokenManager(this.credentials);

  Future<String> getAccessToken({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _accessToken != null &&
        _expiresAt != null &&
        DateTime.now().toUtc().isBefore(
          _expiresAt!.subtract(const Duration(seconds: 60)),
        )) {
      return _accessToken!;
    }

    _tokenRequest ??= _requestToken();
    try {
      await _tokenRequest;
    } finally {
      _tokenRequest = null;
    }
    return _accessToken!;
  }

  Future<void> _requestToken() async {
    final response = await http.post(
      Uri.parse(fuelTokenEndpoint),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: {
        'grant_type': 'client_credentials',
        'client_id': credentials.clientId,
        'client_secret': credentials.clientSecret,
        'scope': 'fuelfinder.read',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Fuel Finder OAuth HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final jsonData = json['data'];
    final token = jsonData['access_token'] as String?;
    final expiresIn = (jsonData['expires_in'] as num?)?.toInt();
    if (token == null || token.isEmpty || expiresIn == null || expiresIn <= 0) {
      throw FormatException(
        'Fuel Finder OAuth response did not contain a valid access_token/expires_in. ${response.body}',
      );
    }
    _accessToken = token;
    _expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
  }

  void invalidate() {
    _accessToken = null;
    _expiresAt = null;
  }
}
