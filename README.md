# Petrol Finder

Flutter Android app + native Android for Cars/Android Auto POI experience.

## What it does

- First run downloads all PFS records in batches, then all fuel prices in batches.
- Stores merged station + price data in `pfs_cache.json` under the Android application-support directory.
- Later runs use `effective-start-timestamp` based on the previous successful sync.
- Uses GPS to find stations inside the configured straight-line radius.
- Uses Google Routes API Compute Routes for driving distance/time.
- Calculates fill cost and round-trip fuel cost from MPG and tank size.
- Displays open/closed state and price age.
- Sends selected station to Google Maps navigation.
- Includes a native Android for Cars POI service.

## Android Auto support

It also supports Android Auto, for finding petrol stations on the go.