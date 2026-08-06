import 'package:astro_journal/core/navigation/double_back_exit_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DoubleBackExitController', () {
    late DoubleBackExitController controller;

    setUp(() {
      controller = DoubleBackExitController(
        confirmDuration: const Duration(seconds: 2),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('첫 번째 뒤로가기는 종료하지 않는다', () {
      expect(controller.shouldExitOnBack(), isFalse);
    });

    test('2초 이내 두 번째 뒤로가기는 종료한다', () {
      expect(controller.shouldExitOnBack(), isFalse);
      expect(controller.shouldExitOnBack(), isTrue);
    });

    test('2초 후에는 다시 첫 입력으로 처리한다', () async {
      expect(controller.shouldExitOnBack(), isFalse);
      await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 50));
      expect(controller.shouldExitOnBack(), isFalse);
    });

    test('reset 후 첫 입력으로 처리한다', () {
      expect(controller.shouldExitOnBack(), isFalse);
      controller.reset();
      expect(controller.shouldExitOnBack(), isFalse);
    });

    test('기본 안내 문구', () {
      expect(
        DoubleBackExitController.defaultMessage,
        '한 번 더 누르면 앱이 종료됩니다.',
      );
    });
  });
}
