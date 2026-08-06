import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/services/object_type_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const classifier = ObjectTypeClassifier();

  group('ObjectTypeClassifier', () {
    test('reclassifies Thor Helmet and Christmas Tree Cluster', () {
      expect(
        classifier.classify(
          id: 'NGC2359',
          catalog: 'ngc',
          name: 'NGC 2359',
          objectType: '기타',
          aliases: const ["Thor's Helmet"],
        ),
        ObjectType.emissionNebula,
      );
      expect(
        classifier.classify(
          id: 'NGC2264',
          catalog: 'ngc',
          name: '크리스마스 트리 성단',
          commonName: '크리스마스 트리 성단',
          objectType: '기타',
        ),
        ObjectType.openCluster,
      );
      expect(
        classifier.classify(
          id: 'Sh2-171',
          catalog: 'sh2',
          name: '북쪽 삼각형 성운',
          objectType: '기타',
        ),
        ObjectType.emissionNebula,
      );
    });

    test('catalog defaults for RCW and vdB', () {
      expect(
        classifier.classify(
          id: 'RCW120',
          catalog: 'rcw',
          name: 'RCW 120',
          objectType: '기타',
        ),
        ObjectType.emissionNebula,
      );
      expect(
        classifier.classify(
          id: 'vdB90',
          catalog: 'vdb',
          name: 'vdB 90',
          objectType: '기타',
        ),
        ObjectType.reflectionNebula,
      );
    });

    test('detects dark nebula targets', () {
      expect(
        classifier.isDarkNebulaTarget(catalog: 'barnard', objectType: '암흑성운'),
        isTrue,
      );
      expect(
        classifier.isDarkNebulaTarget(
          catalog: 'ngc',
          description: 'Dark Nebula region',
        ),
        isFalse,
      );
      expect(
        classifier.isDarkNebulaTarget(
          catalog: 'ngc',
          objectType: '암흑성운',
        ),
        isTrue,
      );
      expect(
        classifier.isDarkNebulaTarget(
          catalog: 'ngc',
          objectType: '발광성운',
          name: '오리온 성운',
        ),
        isFalse,
      );
    });

    test('keeps unknown as other', () {
      expect(
        classifier.classify(
          id: 'X999',
          catalog: 'ngc',
          name: 'X999',
          objectType: '기타',
        ),
        ObjectType.other,
      );
    });
  });
}
