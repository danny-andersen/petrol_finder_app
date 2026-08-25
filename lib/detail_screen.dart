import 'package:flutter/material.dart';

import 'package:petrol_finder_app/common.dart';

class DetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const DetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    Pfs pfs = data['pfs'];
    Map<String, dynamic> rawPfs = pfs.raw;
    final location = rawPfs['location'] as Map<String, dynamic>;
    final amenities = List<String>.from(rawPfs['amenities'] ?? []);
    final opening = rawPfs['opening_times'] as Map<String, dynamic>;
    final usualDays = opening['usual_days'] as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(title: Text(data['trading_name'] ?? 'Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        children: [
          // --- Basic Info ---
          _sectionTitle('Basic Info'),
          _infoRow('Brand', data['brand_name'] ?? 'N/A'),
          _infoRow('Phone', data['public_phone_number'] ?? 'N/A'),
          _infoRow(
            'Temporary Closure',
            data['temporary_closure'] != null
                ? data['temporary_closure'].toString()
                : 'N/A',
          ),
          _infoRow(
            'Motorway Station',
            data['is_motorway_service_station'] != null
                ? data['is_motorway_service_station'].toString()
                : 'N/A',
          ),
          _infoRow(
            'Supermarket Station',
            data['is_supermarket_service_station'] != null
                ? data['is_supermarket_service_station'].toString()
                : 'N/A',
          ),

          const SizedBox(height: 10),

          if (pfs.fuelPrices.isNotEmpty) ...[
            _sectionTitle('Fuel Prices'),

            Column(
              children: pfs.fuelPrices.map((fp) {
                String type = fp['fuel_type'];
                if (type.contains('E')) {
                  type = "Petrol ($type)";
                } else if (type.contains('B')) {
                  type = "Diesel ($type)";
                }
                final price = fp['price'];
                final updated = fp['price_last_updated'];

                return _infoRow(
                  type,
                  '${price.toStringAsFixed(1)}p/L\n${formatDate(updated)}',
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          // --- Location ---
          _sectionTitle('Location'),
          _infoRow('Address 1', location['address_line_1']),
          _infoRow('Address 2', location['address_line_2']),
          _infoRow('City', location['city']),
          _infoRow('County', location['county']),
          _infoRow('Country', location['country']),
          _infoRow('Postcode', location['postcode']),
          _infoRow('Latitude', location['latitude'].toString()),
          _infoRow('Longitude', location['longitude'].toString()),

          const SizedBox(height: 10),

          // --- Amenities ---
          _sectionTitle('Amenities'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: amenities.map((a) => Chip(label: Text(a))).toList(),
          ),

          const SizedBox(height: 10),

          // --- Opening Times ---
          _sectionTitle('Opening Times'),
          ...usualDays.entries.map((e) {
            final day = e.key;
            final info = e.value as Map<String, dynamic>;
            return _infoRow(
              day,
              info['is_24_hours'] == true
                  ? 'Open 24h'
                  : '${info['open']} – ${info['close']}',
            );
          }),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value ?? '—')),
        ],
      ),
    );
  }
}
