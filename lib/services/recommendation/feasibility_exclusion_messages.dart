import '../../data/models/observation_feasibility_result.dart';
import '../observation_feasibility_policy.dart';

abstract final class FeasibilityExclusionMessages {
  static const noFeasibleSlotsMessage = '오늘 밤은 촬영 가능한 시간이 없습니다.';

  static List<String> build({
    required Iterable<ObservationFeasibilityResult> feasibilityResults,
  }) {
    return ObservationFeasibilityPolicy.buildWeatherExclusionMessages(
      results: feasibilityResults,
    );
  }

  static const scheduleEmptyMessage = noFeasibleSlotsMessage;
}
