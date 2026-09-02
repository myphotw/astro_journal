import '../../core/constants/recommendation_score_weights.dart';
import '../../data/models/catalog_object.dart';
import '../../data/models/object_imaging_profile.dart';
import '../../data/models/object_observation_window.dart';
import '../../data/models/observation_context.dart';
import '../celestial_position_service.dart';
import 'light_pollution_score.dart';
import 'mission_score.dart';
import 'moon_score.dart';
import 'season_score.dart';
import 'visibility_score.dart';
import 'weather_score.dart';

/// Aggregates modular score components into a final recommendation score.
class RecommendationScore {
  const RecommendationScore({
    this.missionScore = const MissionScore(),
    this.visibilityScore = const VisibilityScore(),
    this.moonScore = const MoonScore(),
    this.lightPollutionScore = const LightPollutionScore(),
    this.seasonScore = const SeasonScore(),
    this.weatherScore = const WeatherScore(),
  });

  final MissionScore missionScore;
  final VisibilityScore visibilityScore;
  final MoonScore moonScore;
  final LightPollutionScore lightPollutionScore;
  final SeasonScore seasonScore;
  final WeatherScore weatherScore;

  double calculate({
    required CatalogObject object,
    required ObservationContext context,
    required ObjectImagingProfile profile,
    required ObjectObservationWindow window,
    required DateTime evaluationTime,
    required CelestialPositionService positionService,
  }) {
    final scoringContext = context.copyWith(currentTime: evaluationTime);

    final mission = missionScore.calculate(
      object: object,
      context: scoringContext,
    );
    final visibility = visibilityScore.calculate(window: window);
    final moon = moonScore.calculate(
      object: object,
      context: scoringContext,
      positionService: positionService,
      evaluationTime: evaluationTime,
    );
    final lightPollution = lightPollutionScore.calculate(
      context: context,
      profile: profile,
    );
    final season = seasonScore.calculate(
      object: object,
      context: scoringContext,
    );
    final weather = weatherScore.calculate(window: window);

    final weighted = mission * RecommendationScoreWeights.mission +
        visibility * RecommendationScoreWeights.visibility +
        moon * RecommendationScoreWeights.moon +
        lightPollution * RecommendationScoreWeights.lightPollution +
        season * RecommendationScoreWeights.season +
        weather * RecommendationScoreWeights.weather;

    return weighted.clamp(0.0, 100.0);
  }

  /// Condition-only score derived from the existing visibility, Moon, and
  /// weather components. Horizon, obstruction, twilight, and continuous
  /// visibility remain prerequisite gates represented by [window].
  ///
  /// This score is descriptive in the current release and does not add a new
  /// ranking penalty on top of the existing composite score.
  double calculateObservingCondition({
    required CatalogObject object,
    required ObservationContext context,
    required ObjectObservationWindow window,
    required DateTime evaluationTime,
    required CelestialPositionService positionService,
  }) {
    final scoringContext = context.copyWith(currentTime: evaluationTime);
    final visibility = visibilityScore.calculate(window: window);
    final moon = moonScore.calculate(
      object: object,
      context: scoringContext,
      positionService: positionService,
      evaluationTime: evaluationTime,
    );
    final weather = weatherScore.calculate(window: window);
    const totalWeight = RecommendationScoreWeights.visibility +
        RecommendationScoreWeights.moon +
        RecommendationScoreWeights.weather;
    final weighted =
        visibility * RecommendationScoreWeights.visibility +
        moon * RecommendationScoreWeights.moon +
        weather * RecommendationScoreWeights.weather;
    return (weighted / totalWeight).clamp(0.0, 100.0);
  }
}
