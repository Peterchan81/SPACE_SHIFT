// SS CAD TEST — CAD Editor WO §8/§10. "실제 앱 흐름도 확인" — 순수
// 단위 테스트(dxf_round_trip_test.dart)와 별개로, 실제
// [FloorPlanWorkspaceScreen] 위에서 "CAD 파일 업로드" 버튼을 눌렀을 때
// 진짜로 화면까지 데이터가 흘러가는지 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/services/cad_file_upload_service.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';

/// [FloorPlanUploadService]의 테스트 대역과 같은 패턴 — 실제 플랫폼
/// 파일 선택창 없이 미리 만든 DXF 텍스트를 그대로 돌려준다.
class _FakeCadFileUploadService extends CadFileUploadService {
  const _FakeCadFileUploadService(this.content);
  final String content;

  @override
  Future<CadFile?> pickCadFile() async {
    return CadFile(fileName: 'test.dxf', content: content);
  }
}

String _buildRealDxf() {
  const wall = CadWall(
    id: 'w1',
    start: Point2(0.1, 0.1),
    end: Point2(0.1, 0.5),
    thicknessNormalized: 0.01,
    wallType: CadWallType.exterior,
    confidence: 1.0,
  );
  final plan = CadFloorPlan(
    sourceWidthPx: 1000,
    sourceHeightPx: 1000,
    walls: const [wall],
    openings: const [],
    rooms: const [],
    warnings: const [],
  );
  final scale = FloorPlanScale(
    mmPerPixel: 4700 / 400,
    referenceStart: wall.start,
    referenceEnd: wall.end,
    referenceLengthMm: 4700,
    source: ScaleSource.measured,
  );
  return const E2eDxfExporter().export(plan, scale: scale).dxfContent;
}

void main() {
  testWidgets('CAD 파일 업로드 버튼 -> 실제 DXF 파싱 -> 화면에 결과가 반영된다', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dxfContent = _buildRealDxf();
    await tester.pumpWidget(
      MaterialApp(
        home: FloorPlanWorkspaceScreen(
          cadFileUploadService: _FakeCadFileUploadService(dxfContent),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CAD 파일 업로드(DXF)'), findsOneWidget);
    await tester.tap(find.text('CAD 파일 업로드(DXF)'));
    await tester.pumpAndSettle();

    // 가져온 벽 1개, 문/창 0개, 방 0개가 그대로 화면 안내 문구에 반영돼야
    // 한다 — fake 서비스가 준 DXF 내용이 실제로 importDxf를 거쳐
    // setState까지 도달했다는 뜻이다.
    expect(find.textContaining('벽 1개'), findsOneWidget);
  });
}
