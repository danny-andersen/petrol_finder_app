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

## Important implementation notes

1. The Google Routes API is a billed service. Create a restricted Android API key and enable Routes API. Do not hard-code an unrestricted key into source control.
2. Android Auto hosts enforce driver-distraction and template rules. The app uses the Android for Cars App Library rather than a normal Flutter screen for the car display.

## Fuel Finder OAuth credentials

The app reads Fuel Finder OAuth credentials from the bundled asset `assets/config/fuel_finder_credentials.json`. Copy `assets/config/fuel_finder_credentials.json.example` to that filename and replace the placeholders with the credentials supplied by Fuel Finder.

The app obtains a token from `POST https://www.fuel-finder.service.gov.uk/api/v1/oauth/generate_access_token` using `grant_type=client_credentials` and `scope=fuelfinder.read`. Access tokens are cached in memory and reused until they are within 60 seconds of expiry. A `401 Unauthorized` invalidates the token, obtains a fresh token and retries the failed request once.

**Security:** an Android asset is packaged inside the APK and can be extracted. Therefore a client secret stored this way is not confidential against someone who can inspect the APK. Use this arrangement only if Fuel Finder permits native-app client credentials; otherwise put the OAuth client secret behind a backend/token proxy.

Then configure the Google Routes API key in the app's Settings screen.

For Play Store/Android Auto distribution, replace `HostValidator.ALLOW_ALL_HOSTS_VALIDATOR` with a production validator and complete Android for Cars declaration/testing requirements.
