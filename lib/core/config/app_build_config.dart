/// Compile-time configuration embedded in an application build.
///
/// Secrets must be supplied by the release helper and never committed.
class AppBuildConfig {
  AppBuildConfig._();

  static const defaultBackendUrl = 'https://onepieces.synology.me:8443';

  static const backendUrl = String.fromEnvironment(
    'TC_BACKEND_URL',
    defaultValue: defaultBackendUrl,
  );

  static const backendAuthToken = String.fromEnvironment(
    'TC_BACKEND_AUTH_TOKEN',
  );
}
