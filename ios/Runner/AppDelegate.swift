import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let mapsChannelName = "com.example.astro_journal/maps"
  private static let mapsPrefsKey = "google_maps_api_key"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    applyStoredMapsApiKey()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AstroJournalMaps") else {
      return
    }

    let channel = FlutterMethodChannel(
      name: AppDelegate.mapsChannelName,
      binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "syncGoogleMapsApiKey":
        let args = call.arguments as? [String: Any]
        let apiKey = args?["apiKey"] as? String ?? ""
        if apiKey.isEmpty {
          UserDefaults.standard.removeObject(forKey: AppDelegate.mapsPrefsKey)
        } else {
          UserDefaults.standard.set(apiKey, forKey: AppDelegate.mapsPrefsKey)
          GMSServices.provideAPIKey(apiKey)
        }
        result(nil)
      case "getMapsApiKeyStatus":
        let key = UserDefaults.standard.string(forKey: AppDelegate.mapsPrefsKey) ?? ""
        let configured = !key.isEmpty
        result(["configured": configured, "keyLength": key.count])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func applyStoredMapsApiKey() {
    guard let key = UserDefaults.standard.string(forKey: AppDelegate.mapsPrefsKey),
          !key.isEmpty else {
      return
    }
    GMSServices.provideAPIKey(key)
  }
}
