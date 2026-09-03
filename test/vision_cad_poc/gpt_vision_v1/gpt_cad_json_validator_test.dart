// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
//
// 이 테스트의 JSON은 실제 GPT Vision 응답이 아니다 — 파서/검증기
// 로직 자체(형식 오류/cross-reference 오류를 정확히 잡아내는지)만
// 확인하기 위해 손으로 만든 최소 테스트 픽스처다. Vision proposal을
// 대체하지 않는다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/gpt_vision_v1/gpt_cad_json_validator.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v1/gpt_cad_schema.dart';

Map<String, dynamic> _minimalValidJson() => {
      'schemaVersion': 'ss-cad-vision-v1',
      'image': {'widthPx': 400, 'heightPx': 300, 'coordinateSystem': 'top-left-pixel', 'scaleStatus': 'unknown'},
      'floorDomain': {
        'orderedCornerIds': ['C1', 'C2', 'C3', 'C4'],
        'confidence': 0.9,
      },
      'corners': [
        {'id': 'C1', 'x': 10.0, 'y': 10.0, 'kind': 'exteriorConvex', 'confidence': 0.9},
        {'id': 'C2', 'x': 100.0, 'y': 10.0, 'kind': 'exteriorConvex', 'confidence': 0.9},
        {'id': 'C3', 'x': 100.0, 'y': 100.0, 'kind': 'exteriorConvex', 'confidence': 0.9},
        {'id': 'C4', 'x': 10.0, 'y': 100.0, 'kind': 'exteriorConvex', 'confidence': 0.9},
      ],
      'walls': [
        {'id': 'W1', 'type': 'exterior', 'cornerIds': ['C1', 'C2'], 'confidence': 0.9},
        {'id': 'W2', 'type': 'exterior', 'cornerIds': ['C2', 'C3'], 'confidence': 0.9},
        {'id': 'W3', 'type': 'exterior', 'cornerIds': ['C3', 'C4'], 'confidence': 0.9},
        {'id': 'W4', 'type': 'exterior', 'cornerIds': ['C4', 'C1'], 'confidence': 0.9},
      ],
      'spaces': [
        {
          'id': 'S1',
          'label': '거실',
          'semanticType': 'living',
          'boundaryWallIds': ['W1', 'W2', 'W3', 'W4'],
          'confidence': 0.9,
        },
      ],
      'doors': [],
      'windows': [],
      'openings': [],
      'objects': [],
      'relationships': [],
      'dimensionHints': [],
      'reviewReasons': [],
    };

void main() {
  group('GptCadProposal.fromJson — 형태 파싱', () {
    test('올바른 최소 JSON은 정상 파싱된다', () {
      final proposal = GptCadProposal.fromJson(_minimalValidJson());
      expect(proposal.corners, hasLength(4));
      expect(proposal.walls, hasLength(4));
      expect(proposal.spaces, hasLength(1));
    });

    test('confidence가 0..1 범위를 벗어나면 FormatException', () {
      final json = _minimalValidJson();
      (json['corners'] as List)[0] = {'id': 'C1', 'x': 10.0, 'y': 10.0, 'kind': 'exteriorConvex', 'confidence': 1.5};
      expect(() => GptCadProposal.fromJson(json), throwsFormatException);
    });

    test('필수 필드 누락 시 FormatException', () {
      final json = _minimalValidJson();
      (json['corners'] as List)[0] = {'id': 'C1', 'x': 10.0, 'kind': 'exteriorConvex', 'confidence': 0.9};
      expect(() => GptCadProposal.fromJson(json), throwsFormatException);
    });

    test('알 수 없는 enum 값이면 FormatException', () {
      final json = _minimalValidJson();
      (json['walls'] as List)[0] = {'id': 'W1', 'type': 'diagonal', 'cornerIds': ['C1', 'C2'], 'confidence': 0.9};
      expect(() => GptCadProposal.fromJson(json), throwsFormatException);
    });
  });

  group('GptCadJsonValidator — cross-reference 검증', () {
    const validator = GptCadJsonValidator();

    test('올바른 JSON은 검증을 통과한다', () {
      final proposal = GptCadProposal.fromJson(_minimalValidJson());
      expect(() => validator.validate(proposal), returnsNormally);
    });

    test('지원하지 않는 schemaVersion은 거부한다', () {
      final json = _minimalValidJson();
      json['schemaVersion'] = 'ss-cad-vision-v2';
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having(
          (e) => e.errors.join(),
          'errors',
          contains('unsupported schemaVersion'),
        )),
      );
    });

    test('중복 id는 거부한다', () {
      final json = _minimalValidJson();
      (json['walls'] as List)[0] = {'id': 'C1', 'type': 'exterior', 'cornerIds': ['C1', 'C2'], 'confidence': 0.9};
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having((e) => e.errors.join(), 'errors', contains('duplicate id'))),
      );
    });

    test('wall이 존재하지 않는 corner를 참조하면 거부한다', () {
      final json = _minimalValidJson();
      (json['walls'] as List)[0] = {
        'id': 'W1',
        'type': 'exterior',
        'cornerIds': ['C1', 'C99'],
        'confidence': 0.9,
      };
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having(
          (e) => e.errors.join(),
          'errors',
          contains('unknown corner id "C99"'),
        )),
      );
    });

    test('space가 존재하지 않는 wall을 참조하면 거부한다', () {
      final json = _minimalValidJson();
      (json['spaces'] as List)[0] = {
        'id': 'S1',
        'label': '거실',
        'semanticType': 'living',
        'boundaryWallIds': ['W1', 'W99'],
        'confidence': 0.9,
      };
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having(
          (e) => e.errors.join(),
          'errors',
          contains('unknown wall id "W99"'),
        )),
      );
    });

    test('door가 존재하지 않는 hostWallId를 참조하면 거부한다', () {
      final json = _minimalValidJson();
      json['doors'] = [
        {
          'id': 'D1',
          'hostWallId': 'W99',
          'startT': 0.2,
          'endT': 0.4,
          'connectsSpaceIds': ['S1'],
          'confidence': 0.8,
        },
      ];
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having(
          (e) => e.errors.join(),
          'errors',
          contains('unknown hostWallId "W99"'),
        )),
      );
    });

    test('door의 startT >= endT면 거부한다', () {
      final json = _minimalValidJson();
      json['doors'] = [
        {
          'id': 'D1',
          'hostWallId': 'W1',
          'startT': 0.6,
          'endT': 0.4,
          'connectsSpaceIds': ['S1'],
          'confidence': 0.8,
        },
      ];
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having(
          (e) => e.errors.join(),
          'errors',
          contains('invalid interval'),
        )),
      );
    });

    test('FloorDomain이 서로 다른 corner 3개 미만이면 거부한다', () {
      final json = _minimalValidJson();
      json['floorDomain'] = {
        'orderedCornerIds': ['C1', 'C2'],
        'confidence': 0.9,
      };
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having(
          (e) => e.errors.join(),
          'errors',
          contains('at least 3 distinct corners'),
        )),
      );
    });

    test('좌표가 이미지 경계를 심하게 벗어나면 거부한다', () {
      final json = _minimalValidJson();
      (json['corners'] as List)[0] = {'id': 'C1', 'x': 10000.0, 'y': 10.0, 'kind': 'exteriorConvex', 'confidence': 0.9};
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having(
          (e) => e.errors.join(),
          'errors',
          contains('outside image bounds'),
        )),
      );
    });

    test('relationship이 존재하지 않는 entity를 참조하면 거부한다', () {
      final json = _minimalValidJson();
      json['relationships'] = [
        {'entityA': 'S1', 'entityB': 'S99', 'relation': 'adjacent'},
      ];
      final proposal = GptCadProposal.fromJson(json);
      expect(
        () => validator.validate(proposal),
        throwsA(isA<GptCadValidationException>().having(
          (e) => e.errors.join(),
          'errors',
          contains('unknown entityB'),
        )),
      );
    });
  });
}
