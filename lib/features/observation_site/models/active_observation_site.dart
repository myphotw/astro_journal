import '../../../data/models/imaging_suitability_assessment.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/site_horizon_profile.dart';

enum ActiveObservationSiteKind { currentLocation, savedSite }

class ActiveObservationSite {
  const ActiveObservationSite._({
    required this.kind,
    this.site,
    this.currentLatitude,
    this.currentLongitude,
    this.temporaryTrackingOverride,
    this.temporaryEquipmentOverrideId,
  });

  const ActiveObservationSite.currentLocation({
    double? latitude,
    double? longitude,
    TrackingMode? temporaryTrackingOverride,
    String? temporaryEquipmentOverrideId,
  }) : this._(
         kind: ActiveObservationSiteKind.currentLocation,
         currentLatitude: latitude,
         currentLongitude: longitude,
         temporaryTrackingOverride: temporaryTrackingOverride,
         temporaryEquipmentOverrideId: temporaryEquipmentOverrideId,
       );

  const ActiveObservationSite.saved(
    ObservationSite site, {
    TrackingMode? temporaryTrackingOverride,
    String? temporaryEquipmentOverrideId,
  }) : this._(
         kind: ActiveObservationSiteKind.savedSite,
         site: site,
         temporaryTrackingOverride: temporaryTrackingOverride,
         temporaryEquipmentOverrideId: temporaryEquipmentOverrideId,
       );

  final ActiveObservationSiteKind kind;
  final ObservationSite? site;
  final double? currentLatitude;
  final double? currentLongitude;
  final TrackingMode? temporaryTrackingOverride;
  final String? temporaryEquipmentOverrideId;

  bool get isCurrentLocation =>
      kind == ActiveObservationSiteKind.currentLocation;
  bool get isSavedSite => kind == ActiveObservationSiteKind.savedSite;
  String? get selectedSiteId => site?.id;
  String get displayName => site?.name ?? '현재 위치';
  double? get latitude => site?.latitude ?? currentLatitude;
  double? get longitude => site?.longitude ?? currentLongitude;
  TrackingMode get effectiveTrackingMode =>
      temporaryTrackingOverride ?? site?.trackingMode ?? TrackingMode.altAz;
  String? get effectiveEquipmentId =>
      temporaryEquipmentOverrideId ?? site?.defaultEquipmentId;
  SiteHorizonProfile get horizonProfile => SiteHorizonProfile(
    points: site?.horizonPoints ?? const [],
    blockedRanges: site?.blockedAzimuthRanges ?? const [],
  );

  ActiveObservationSite copyWithCurrentLocation({
    required double latitude,
    required double longitude,
  }) => ActiveObservationSite.currentLocation(
    latitude: latitude,
    longitude: longitude,
    temporaryTrackingOverride: temporaryTrackingOverride,
    temporaryEquipmentOverrideId: temporaryEquipmentOverrideId,
  );

  ActiveObservationSite copyWithOverrides({
    TrackingMode? trackingMode,
    String? equipmentId,
    bool clearEquipment = false,
  }) {
    final nextEquipment = clearEquipment
        ? null
        : (equipmentId ?? temporaryEquipmentOverrideId);
    if (isSavedSite) {
      return ActiveObservationSite.saved(
        site!,
        temporaryTrackingOverride: trackingMode ?? temporaryTrackingOverride,
        temporaryEquipmentOverrideId: nextEquipment,
      );
    }
    return ActiveObservationSite.currentLocation(
      latitude: currentLatitude,
      longitude: currentLongitude,
      temporaryTrackingOverride: trackingMode ?? temporaryTrackingOverride,
      temporaryEquipmentOverrideId: nextEquipment,
    );
  }
}
