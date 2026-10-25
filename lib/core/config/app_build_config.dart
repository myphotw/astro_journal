/// Compile-time configuration embedded in an application build.
///
/// Secrets must be supplied by the release helper and never committed.
class AppBuildConfig {
  AppBuildConfig._();

  static const defaultBackendUrl = '';

  static const backendUrl = String.fromEnvironment(
    'TC_BACKEND_URL',
    defaultValue: defaultBackendUrl,
  );

  static const backendUrlInternal = String.fromEnvironment(
    'TC_BACKEND_URL_INTERNAL',
  );

  static const backendUrlExternal = String.fromEnvironment(
    'TC_BACKEND_URL_EXTERNAL',
  );

  static const backendAuthToken = String.fromEnvironment(
    'TC_BACKEND_AUTH_TOKEN',
  );
}
