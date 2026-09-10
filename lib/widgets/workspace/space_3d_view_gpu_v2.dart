import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import '../../models/space_scene_v2.dart';
import '../../services/iso_cutaway.dart';
import '../../theme/space_shift_colors.dart';

/// WO092 §6 — 3D 아이소/3D 투시는 같은 실시간 scene을 쓰고 카메라
/// 배치만 다르다. [isometric]은 기존과 같은 "위에서 내려다보는" 초기
/// 시점, [perspective]는 방 안 눈높이에서 보는 초기 시점이다 — 둘 다
/// 자유롭게 회전/확대할 수 있어 사용자가 두 모드를 완전히 다른 화면으로
/// 느끼지 않는다(같은 재질 변경이 양쪽에 그대로 반영된다).
enum Space3DCameraMode { isometric, perspective }

/// SpaceScene V2 GPU 렌더러 — Windows 실기 재조사(3D) 결론에 따른
/// renderer architecture 교체. CPU coarse-tile z-buffer([space_3d_view_v2.dart],
/// 삭제하지 않고 보존)는 실기에서 벽/바닥 경계가 심하게 계단화된 큰
/// 사각 block으로 보였다 — tile 해상도를 올려서 증상만 가리는 대신,
/// 실제 GPU 삼각형 rasterization + 실제 depth buffer를 쓰는 `three_js`
/// (ANGLE 기반 네이티브 렌더러, Windows/Android/Web 모두 stable
/// Flutter SDK에서 동작, MIT 라이선스)로 렌더러 자체를 교체한다.
///
/// [SpaceSceneV2](mesh 데이터, mm 단위 world 좌표)는 그대로 재사용한다.
///
/// WO092 §5 — "3D 객체 선택 및 편집"을 위해 벽/바닥/천장을 더 이상
/// 색상별로 합쳐 그리지 않고 객체 하나당 mesh 하나로 만든다([SpaceObjectIdentityV2]가
/// 이미 이 순간을 위해 준비돼 있었다 — WO092 이전 코드 주석 참고).
/// 화면을 탭하면 그 지점으로 ray를 쏴 실제로 부딪힌 mesh의 identity를
/// [onObjectSelected]로 돌려주고, 선택된 mesh는 emissive 강조로 시각
/// 구분한다.
///
/// WO093/WO094/WO095-A — "3D 아이소 Cutaway/Dollhouse 표현 수정"은 세
/// 번 모두 "벽 하나하나에 대해 무엇을 할지" 판정하는 방식이었다 — 카메라
/// 시선을 가로막는 벽을 통째로 숨기거나(WO093/094), 카메라 반대편(뒤쪽)
/// 벽만 골라 전체 높이로 남기고 나머지를 낮은 담장으로 대체하는
/// 방식(WO095-A)이었다. 실측(평면도.PNG, 벽 86개)으로 재현하면 두 방식
/// 모두 실패했다 — 벽이 조밀하게 몰린 작은 방 클러스터가 있으면 그
/// 구역 전체가 "덩어리"처럼 남거나("어딘가의 방 하나를 가리는 벽은
/// 항상 있다"는 구조적 한계), WO095-A 재현에서는 "뒤쪽"으로 뽑힌 9개
/// 벽 전부가 건물 외곽이 아니라 한 구석에 몰린 작은 방의 내부
/// 칸막이벽이었다(사용자 PC1 실기 판정: "왼쪽 위에 큰 full-height 벽
/// 덩어리 + 나머지는 얕은 3D 평면도처럼 보임").
///
/// WO095-B — 벽 단위 판정을 완전히 버리고, 실제 건축 Dollhouse/section
/// view 도구처럼 "건물 전체에 적용되는 단일 GPU 절단면(clip plane)"으로
/// 교체했다:
/// - 벽 mesh는 항상 원래 전체 높이 그대로 하나만 만든다(더 이상 낮은
///   높이 대체 mesh를 만들지 않는다).
/// - [_applyIsoWallDisplay]가 매 프레임 [computeIsoSectionCut](iso_cutaway.dart)로
///   "카메라 쪽 근처 몇 %"를 건물 전체 bounding box + 카메라 방향
///   기준으로 계산해 [three.Plane] 하나를 세우고,
///   `renderer.clippingPlanes`에 적용한다 — three_js(표준 three.js와
///   동일한 GPU clipping 기능, `Material.clipping` + `AngleRenderer.
///   clippingPlanes`/`localClippingEnabled`)가 정점/프래그먼트 단위로
///   잘라내므로, 벽이 몇 개든 어떻게 분포하든 항상 매끈한 단면 하나로
///   결과가 일관된다.
/// - 이 절단면은 벽 재질에만 적용한다([_addObjectMesh]의 `clipping`
///   인자) — 바닥/천장 재질에는 적용하지 않아 바닥은 항상 전체가
///   보인다.
/// - [computeIsoSectionCutFraction]으로 절단 비율을 카메라 줌 거리에
///   연동한다 — 확대(카메라가 가까워짐)할수록 절단 비율이 줄어 더 많이
///   열린다("작은 방을 확대하면 내부까지 보여야 한다" 요구 대응).
/// - 3D 투시([Space3DCameraMode.perspective])는 `clippingPlanes`를 항상
///   빈 리스트로 둬서 이 로직의 영향을 전혀 받지 않는다(WO095-B 지시 —
///   "3D 투시는 이번 단계에서 수정하지 않는다").
/// - 탭 선택([_handleTapUp])은 GPU 클리핑을 CPU 레이캐스터가 모르기
///   때문에, 히트 지점이 절단면의 "잘려나간" 쪽에 있으면 그 히트를
///   건너뛰고 다음 히트를 본다 — 화면에 안 보이는(잘린) 부분이 선택되는
///   혼란을 막는다.
///
/// WO094에서 함께 고친 나머지 두 가지는 이번에도 그대로 유지한다:
/// 1) `three_js_controls`의 [OrbitControls] 대신 Flutter 자체
///    [GestureDetector.onScale*]로 직접 구면좌표 카메라를 돌린다 — 회전/
///    확대 각도에 인위적 제한을 두지 않는다.
/// 2) '전체 화면'은 [onToggleFullscreen] 콜백으로 상위 위젯에게 레이아웃
///    전환만 요청하고, 이 State/three_js 인스턴스는 절대 다시 만들어지지
///    않는다(같은 [GlobalKey]로 위젯 위치만 옮긴다).
class Space3DViewGpuV2 extends StatefulWidget {
  const Space3DViewGpuV2({
    super.key,
    required this.scene,
    this.isFullscreen = false,
    this.onExitTo2D,
    this.onToggleFullscreen,
    this.cameraMode = Space3DCameraMode.isometric,
    this.selectedObjectId,
    this.onObjectSelected,
  });

  final SpaceSceneV2 scene;

  /// true면 지금 이 위젯이 전체 화면 레이아웃으로 표시되고 있다는 뜻 —
  /// "전체 화면" 대신 "닫기" 버튼을 보여준다. 실제 전체화면 진입/종료는
  /// [onToggleFullscreen]을 통해 상위 위젯(레이아웃)에게 위임한다.
  final bool isFullscreen;
  final VoidCallback? onExitTo2D;
  final VoidCallback? onToggleFullscreen;
  final Space3DCameraMode cameraMode;

  /// 현재 선택된 3D 객체의 [SpaceObjectIdentityV2.objectId](예:
  /// `wall:wall-3`, `floor:room-1`, `ceiling:room-1`) — 화면 밖(우측
  /// 작업 패널)에서 선택이 바뀌어도(예: 작업 목록에서 다시 선택) 이
  /// 값을 통해 3D의 강조 표시가 함께 따라온다.
  final String? selectedObjectId;

  /// 사용자가 벽/바닥/천장을 탭해 선택하면(§5) 그 [SpaceObjectIdentityV2]를
  /// 돌려준다. 빈 곳을 탭하면 null을 돌려준다(선택 해제).
  final ValueChanged<SpaceObjectIdentityV2?>? onObjectSelected;

  @override
  State<Space3DViewGpuV2> createState() => _Space3DViewGpuV2State();
}

/// 선택 강조에 쓰는 emissive 색 — 어떤 벽/바닥/천장 기본색과도 뚜렷이
/// 구분되는 파란 계열 glow(재질 색 자체를 바꾸지 않고 위에 얹는
/// 방식이라 "지금 무슨 색인지"는 그대로 보이면서 "선택됨"만 추가로
/// 보인다).
const int _kSelectionEmissiveHex = 0x2F6FED;
const double _kSelectionEmissiveIntensity = 0.55;

class _Space3DViewGpuV2State extends State<Space3DViewGpuV2> {
  late three.ThreeJS _threeJs;
  final Map<String, three.Mesh> _meshByObjectId = {};
  final Map<String, SpaceObjectIdentityV2> _identityByObjectId = {};
  String? _appliedHighlightId;

  /// WO095-B가 쓰던 절단면 — WO099부터 [_applyIsoWallDisplay]가 더 이상
  /// 갱신하지 않는다(§ 그 메서드 문서 참고, 항상 원점 평면인 채로
  /// 남는다). [_performTapSelection]의 관련 분기는 `renderer.
  /// clippingPlanes`가 항상 비어 있으므로 실행되지 않는 죽은 코드다 —
  /// 향후 절단면 기능을 다시 켤 때 필드/분기를 되살리기 쉽도록 지금
  /// 지우지 않고 남겨 둔다.
  final three.Plane _sectionCutPlane = three.Plane();

  // WO094 — three_js_controls의 OrbitControls(raw pointer 기반이라
  // Android 실기에서 실제로 동작하는지 코드만으로 확신할 수 없었다)
  // 대신, 직접 구면좌표 카메라를 돌린다. target은 기본은 scene 중심이지만
  // WO098부터 우/중클릭 drag로 pan도 가능하다(§5).
  //
  // WO098 §8 root-cause — 예전엔 이 값을 [GestureDetector.onScale*]로
  // 갱신했지만, three_js 패키지 자체가 렌더 트리 내부(three_js_core/
  // others/peripherals.dart의 [Peripherals] 위젯, `_threeJs.build()`가
  // 내부적으로 감싸는 위젯)에 **자기 자신의 GestureDetector+Listener**를
  // 이미 심어 둔다(OrbitControls 등 JS 스타일 addEventListener API를
  // 흉내내려는 목적 — 이 앱은 OrbitControls를 안 쓰지만 Peripherals
  // 자체는 항상 존재한다). 그 결과 같은 pointer 스트림에 대해 서로 다른
  // GestureDetector 두 개(우리 것 + three_js 내부 것)가 각자
  // ScaleGestureRecognizer를 만들어 같은 gesture arena에서 경쟁하게
  // 되고, 이것이 실측된 "360° 회전이 되다 안 되다 함/거의 안 됨" 증상의
  // root cause였다. 또한 [GestureDetector.onScale*]는애초에 마우스 휠
  // (PointerScrollEvent)을 받을 수 없고 마우스 버튼(좌/우/중)을 구분하지도
  // 못해 §4(휠 zoom)/§5(우/중클릭 pan) 자체가 구조적으로 구현 불가능했다.
  //
  // 수정: [Listener](gesture arena에 참여하지 않고 raw [PointerEvent]를
  // 그대로 받는다 — three_js 내부 GestureDetector와 경쟁할 대상 자체가
  // 없다)로 바꿔 이 문제를 근본적으로 없앤다. 부수적으로 마우스 버튼 구분
  // (event.buttons)과 [PointerScrollEvent](휠)를 직접 다룰 수 있게 되어
  // §4/§5가 자연스럽게 구현된다.
  double _orbitTargetX = 0, _orbitTargetY = 0, _orbitTargetZ = 0;
  double _orbitDistance = 1000;
  double _orbitAzimuth = 0;
  double _orbitPolar = math.pi / 4;
  double _minOrbitDistance = 1, _maxOrbitDistance = 100000;

  /// pointer id -> 이 위젯 기준 마지막 local position(드래그 delta 계산용).
  final Map<int, Offset> _activePointers = {};

  /// 회전/pan을 구동하는 대표 pointer(가장 먼저 눌린 것). 두 번째 이상
  /// pointer는 회전/pan에 관여하지 않는다(단순 보조 접촉으로 무시).
  int? _primaryPointerId;

  /// true면 대표 pointer가 pan(우/중클릭)을, false면 회전(좌클릭/터치)을
  /// 구동한다 — pointer down 시점의 버튼 상태로 한 번만 결정한다.
  bool _primaryIsPan = false;

  /// 대표 pointer가 눌린 지점 — 이동량이 [kTouchSlop] 미만인 채로
  /// 떼어지면 회전/pan이 아니라 객체 선택 tap으로 취급한다(§ 기존
  /// onTapUp 동작 보존).
  Offset? _tapDownPosition;
  bool _possibleTap = false;

  @override
  void initState() {
    super.initState();
    // WO094 PC1 실기 재검증 FAIL — 렌더러 기본 clearColor가 0x000000(불투명
    // 검정)이라 scene에 배경을 따로 설정하지 않으면 배경이 항상 검정으로
    // 보인다(3D 모델 문제가 아니라 렌더러 초기화 문제). 사용자가 요구한
    // "밝은 배경"에 맞춰 이 앱의 기본 배경색(SpaceShiftColors.background,
    // 흰색)으로 명시적으로 지정한다.
    // WO095-B — GPU clipping(Architectural Dollhouse section cut)을 쓰려면
    // renderer가 localClippingEnabled=true로 초기화돼 있어야 material의
    // clippingPlanes/clipping이 실제로 반영된다(three_js_angle_renderer
    // 소스 확인 — Settings.localClippingEnabled → AngleRenderer.render()가
    // 매 프레임 다시 읽는 필드). clippingPlanes 자체(어떤 평면을 쓸지)는
    // 매 프레임 [_applyIsoWallDisplay]가 갱신한다.
    _threeJs = three.ThreeJS(
      onSetupComplete: () {},
      setup: _setup,
      settings: three.Settings(
        clearColor: 0xFFFFFF,
        clearAlpha: 1.0,
        localClippingEnabled: true,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant Space3DViewGpuV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene != widget.scene) {
      _rebuildMeshes(widget.scene);
      _applyHighlight();
      _applyIsoWallDisplay();
    } else if (oldWidget.selectedObjectId != widget.selectedObjectId) {
      _applyHighlight();
    }
    // WO092 §6 — "3D 아이소"/"3D 투시" 탭 전환은 이 위젯을 새로
    // 마운트하지 않고 같은 State에 다른 [cameraMode]만 새로 전달한다
    // (viewMode만 바뀌고 scene은 그대로라 Flutter가 State를 재사용).
    // 카메라 시작 위치를 그때마다 다시 계산하지 않으면 탭을 눌러도
    // 화면이 이전 모드의 카메라 위치 그대로 멈춰 있게 된다.
    if (oldWidget.cameraMode != widget.cameraMode) {
      _resetCamera();
      // WO093 §1 — 투시로 전환하면 cutaway를 완전히 끈다(모든 벽 원복).
      _applyIsoWallDisplay();
    }
  }

  @override
  void dispose() {
    _threeJs.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    final scene3d = widget.scene;
    final radius = scene3d.boundingRadius <= 0 ? 1000.0 : scene3d.boundingRadius;
    final farPlane = radius * 40 + 10000;
    _minOrbitDistance = radius * 0.05 + 1;
    _maxOrbitDistance = radius * 12 + 5000;

    _threeJs.camera = three.PerspectiveCamera(
      45,
      _threeJs.width / _threeJs.height,
      radius * 0.01 + 1,
      farPlane,
    );
    _threeJs.scene = three.Scene();

    // WO094 §4.E — "검정 배경 + 회색 벽체 골격" 인상을 줄인다. 기존에는
    // ambient 0.55 + 방향광 2개뿐이라, 광원을 등진 면은 원래 재질色과
    // 무관하게 어둡게 죽어 전체적으로 칙칙한 회색으로 보였다. 건축
    // 인테리어 뷰어(Zillow/Matterport dollhouse 등)처럼 그림자 대비를
        // 낮추고 고르게 밝힌다 — ambient를 크게 올리고 사방에서 오는 fill
    // light 3개를 더해, 벽의 실제 재질 색(흰색 벽/우드 바닥/타일)이
    // 어느 각도에서 봐도 그 색 그대로 보이게 한다.
    _threeJs.scene.add(three.AmbientLight(0xffffff, 0.85));
    final keyLight = three.DirectionalLight(0xffffff, 0.55);
    keyLight.position.setValues(-radius * 0.6, radius * 1.4, radius * 0.5);
    _threeJs.scene.add(keyLight);
    final fillLight1 = three.DirectionalLight(0xffffff, 0.35);
    fillLight1.position.setValues(radius * 0.8, radius * 0.6, -radius * 0.6);
    _threeJs.scene.add(fillLight1);
    final fillLight2 = three.DirectionalLight(0xffffff, 0.3);
    fillLight2.position.setValues(radius * 0.6, radius * 0.9, radius * 0.9);
    _threeJs.scene.add(fillLight2);
    final fillLight3 = three.DirectionalLight(0xffffff, 0.25);
    fillLight3.position.setValues(-radius * 0.7, radius * 0.5, -radius * 0.4);
    _threeJs.scene.add(fillLight3);

    _rebuildMeshes(scene3d);
    _applyHighlight();

    _resetCamera();
    _applyIsoWallDisplay();

    _threeJs.windowResizeUpdate = (Size newSize) {
      final camera = _threeJs.camera;
      if (camera is three.PerspectiveCamera && newSize.height > 0) {
        camera.aspect = newSize.width / newSize.height;
        camera.updateProjectionMatrix();
      }
    };

    _threeJs.addAnimationEvent((dt) {
      // WO093 §5 — 회전/확대로 카메라 위치가 매 프레임 바뀔 수 있어,
      // cutaway 판정도 매 프레임 다시 계산한다. 벽/방 개수가 이 앱
      // 규모(수십 개 이내)라 매 프레임 재계산해도 비용이 미미하다.
      _applyIsoWallDisplay();
    });
  }

  /// WO092 §5 — 기존에는 색상별로 삼각형을 합쳐 mesh 몇 개만 만들었지만
  /// (재질 편집 UI가 없던 시절엔 그걸로 충분했다), 이제 "이 벽만",
  /// "이 방 바닥만" 선택/강조/재질 변경이 가능해야 하므로 객체(벽 1개/
  /// 바닥 1개/천장 1개)당 mesh 1개로 만든다. mesh 개수가 색상 개수 몇
  /// 개에서 벽/방 개수만큼(보통 수십 개 이내)으로 늘지만 이 앱 규모에서
  /// 문제되지 않는다.
  void _rebuildMeshes(SpaceSceneV2 scene3d) {
    for (final mesh in _meshByObjectId.values) {
      _threeJs.scene.remove(mesh);
    }
    _meshByObjectId.clear();
    _identityByObjectId.clear();
    _appliedHighlightId = null;

    for (final wall in scene3d.wallMeshes) {
      // WO099 §4 — 벽은 항상 원래 전체 높이 실제 solid geometry로 만든다
      // (WO095-B처럼 별도 낮은 높이 mesh를 만들지 않는다). 대신 재질을
      // [three.BackSide]로 그려 "카메라를 향한 면"만 자동으로 렌더링에서
      // 빠지게 한다 — 벽이 몇 개든, 카메라가 어디에 있든 항상 지금
      // 카메라를 막는 면만 사라지고 그 뒤(방 내부를 감싸는 반대쪽 벽의
      // 안쪽 면)가 보인다. 벽 ID/threshold 판정도, GPU clip-plane도
      // 전혀 없다(§1 반복 금지 대상이 아님 — 아예 다른 방법).
      _addObjectMesh(wall.identity, wall.triangles, doubleSided: false, useBackSide: true);
    }
    for (final floor in scene3d.floorMeshes) {
      _addObjectMesh(floor.identity, floor.triangles, doubleSided: true);
    }
    // WO092 §4 — 천장은 방 안쪽(-Y)을 향하는 단면(FrontSide)만 그린다.
    // 기본 아이소 카메라(위에서 내려다봄)는 이 면의 뒤쪽을 보게 되어
    // backface culling으로 자연히 안 보인다 — 천장이 실제로 존재하면서도
    // 기존 "천장 없는 dollhouse" 시야를 그대로 유지하는 핵심 트릭이다.
    // 카메라가 방 안(천장 아래)으로 들어가면(3D 투시 등) 정상적으로
    // 앞면이 보인다.
    for (final ceiling in scene3d.ceilingMeshes) {
      _addObjectMesh(ceiling.identity, ceiling.triangles, doubleSided: false);
    }
    // WO099 §8 — Phase A 최소 가구(sofa/table/bed). 벽과 달리 카메라를
    // 막을 만큼 크지 않으므로 일반 DoubleSide로 그린다.
    for (final furniture in scene3d.furnitureMeshes) {
      _addObjectMesh(furniture.identity, furniture.triangles, doubleSided: true);
    }
    // WO102 §5 — window frame/glass. 둘 다 벽처럼 카메라를 크게 막지
    // 않으므로 일반 DoubleSide로 그린다(§4/§9 — 벽과 달리 새 rendering
    // 트릭이 필요 없다).
    for (final window in scene3d.windowMeshes) {
      _addObjectMesh(window.frameIdentity, window.frameTriangles, doubleSided: true);
      _addObjectMesh(window.glassIdentity, window.glassTriangles, doubleSided: true);
    }
  }

  /// [useBackSide]가 true(벽)면 [doubleSided]와 무관하게 항상
  /// [three.BackSide]로 그린다 — §4/[_rebuildMeshes] 문서 참고. [clipping]은
  /// WO095-B가 쓰던 GPU 절단면 연결 자리인데, WO099부터
  /// [_applyIsoWallDisplay]가 절단면을 항상 비워서 지금은 사실상
  /// 아무 효과가 없다(향후 명시적 단면 도구를 다시 붙일 때를 위해
  /// 매개변수 자체는 남겨 둔다).
  void _addObjectMesh(
    SpaceObjectIdentityV2 identity,
    List<SpaceTriangleV2> triangles, {
    required bool doubleSided,
    bool clipping = false,
    bool useBackSide = false,
  }) {
    if (triangles.isEmpty) return;
    final positions = Float32List(triangles.length * 9);
    var i = 0;
    for (final tri in triangles) {
      positions[i++] = tri.a.x;
      positions[i++] = tri.a.y;
      positions[i++] = tri.a.z;
      positions[i++] = tri.b.x;
      positions[i++] = tri.b.y;
      positions[i++] = tri.b.z;
      positions[i++] = tri.c.x;
      positions[i++] = tri.c.y;
      positions[i++] = tri.c.z;
    }
    final geometry = three.BufferGeometry();
    geometry.setAttribute(
      three.Attribute.position,
      three.Float32BufferAttribute(positions, 3),
    );
    // 삼각형끼리 vertex를 공유하지 않게 만들어(각 삼각형이 자기 정점
    // 3개를 독립적으로 가짐) computeVertexNormals가 인접 삼각형과
    // 평균내지 않고 그대로 face normal을 쓰게 한다 — flat shading이
    // 건축 shell에 더 적합하다(부드러운 곡면이 아니라 뚜렷한 벽/바닥
    // 경계가 보여야 한다).
    geometry.computeVertexNormals();

    final colorHex = _colorToHex(identity.color ?? const Color(0xFFC9C2B4));
    final side = useBackSide
        ? three.BackSide
        : (doubleSided ? three.DoubleSide : three.FrontSide);
    final material = three.MeshLambertMaterial({
      three.MaterialProperty.color: colorHex,
      three.MaterialProperty.side: side,
      three.MaterialProperty.clipping: clipping,
    });
    final mesh = three.Mesh(geometry, material);
    mesh.userData['objectId'] = identity.objectId;
    _threeJs.scene.add(mesh);
    _meshByObjectId[identity.objectId] = mesh;
    _identityByObjectId[identity.objectId] = identity;
  }

  int _colorToHex(Color color) {
    final r = (color.r * 255).round() & 0xFF;
    final g = (color.g * 255).round() & 0xFF;
    final b = (color.b * 255).round() & 0xFF;
    return (r << 16) | (g << 8) | b;
  }

  /// 이전 선택 mesh의 emissive를 지우고, 새 선택 mesh에 emissive
  /// 강조를 얹는다. [widget.selectedObjectId]가 가리키는 mesh가 이번
  /// scene에 없으면(예: 다시 분석되어 id가 바뀜) 조용히 아무 강조도
  /// 하지 않는다.
  void _applyHighlight() {
    if (_appliedHighlightId != null) {
      final previous = _meshByObjectId[_appliedHighlightId];
      final material = previous?.material;
      if (material is three.MeshLambertMaterial) {
        material.emissive = three.Color.fromHex32(0x000000);
        material.needsUpdate = true;
      }
    }
    _appliedHighlightId = null;

    final selectedId = widget.selectedObjectId;
    if (selectedId == null) return;
    final selected = _meshByObjectId[selectedId];
    final material = selected?.material;
    if (material is three.MeshLambertMaterial) {
      material.emissive = three.Color.fromHex32(_kSelectionEmissiveHex);
      material.emissiveIntensity = _kSelectionEmissiveIntensity;
      material.needsUpdate = true;
      _appliedHighlightId = selectedId;
    }
  }

  /// WO099 §1/§4/§17 — WO095-B의 camera-facing GPU 절단면(건물 전체를
  /// 카메라 쪽에서 잘라내는 방식)은 "전체 공간 구조가 한눈에 읽혀야
  /// 한다"(§0 우선순위 1)와 정면으로 충돌한다 — 잘려나간 근처 방은
  /// 아예 안 보이기 때문이다. cut fraction 숫자를 다시 조정하는 대신
  /// (§1 "반복 금지"), 벽이 카메라를 막지 않게 하는 방법 자체를
  /// [_addObjectMesh]의 벽 재질을 [three.BackSide]로 바꾸는 것으로
  /// 교체했다(§4 조사 결론 — 카메라를 향한 면만 자동으로 컬링되어,
  /// 회전해도 항상 "지금 카메라를 막는 벽"만 사라지고 나머지는 그대로
  /// 남는다. 벽 ID/threshold 판정이 전혀 없다).
  ///
  /// 이 메서드와 [iso_cutaway.dart]는 삭제하지 않는다 — 향후 "사용자가
  /// 직접 트리거하는 단면 보기" 같은 명시적 도구로 재사용할 수 있는
  /// 자리로 남겨 둔다(§12 "같은 Scene을 유지"). 지금은 항상 절단면을
  /// 비워 아이소/투시 모두 영향을 받지 않는다.
  void _applyIsoWallDisplay() {
    final renderer = _threeJs.renderer;
    if (renderer == null) return;
    renderer.clippingPlanes = const [];
  }

  /// WO092 §5 — 화면을 탭한 지점으로 실제 ray를 쏴서 부딪힌 mesh를
  /// 찾는다. WO098 — [TapUpDetails] 대신 순수 [Offset]을 받는다(호출부가
  /// 이제 [GestureDetector.onTapUp]이 아니라 [Listener]의 pointer-up
  /// tap 판정이기 때문 — 아래 [_handlePointerUp] 참고).
  void _performTapSelection(Offset localPosition) {
    if (widget.onObjectSelected == null) return;
    final width = _threeJs.width;
    final height = _threeJs.height;
    if (width <= 0 || height <= 0) return;
    final ndcX = (localPosition.dx / width) * 2 - 1;
    final ndcY = -(localPosition.dy / height) * 2 + 1;

    final raycaster = three.Raycaster();
    raycaster.setFromCamera(three.Vector2(ndcX, ndcY), _threeJs.camera);
    final hits = raycaster.intersectObjects(
      _meshByObjectId.values.toList(growable: false),
      false,
    );
    // WO095-B — GPU 절단면(§클래스 문서)은 화면에 실제로 무엇이 보이는지
    // 결정하지만, CPU 레이캐스터는 그 절단면을 모르고 원본 전체 높이
    // geometry 그대로 교차를 계산한다. 그래서 hit들을 거리순(가까운
    // 순서, [Raycaster.intersectObjects]가 이미 정렬해 돌려준다)으로
    // 훑으면서, 절단면의 "잘려나간"쪽에 있는 hit는 건너뛰고 실제로 화면에
    // 보이는 첫 hit만 선택한다 — 그렇지 않으면 화면에 안 보이는(잘린)
    // 부분을 탭해도 선택되는 혼란이 생긴다.
    final clippingActive =
        widget.cameraMode == Space3DCameraMode.isometric &&
        (_threeJs.renderer?.clippingPlanes.isNotEmpty ?? false);
    for (final hit in hits) {
      final point = hit.point;
      if (clippingActive && point != null && _sectionCutPlane.distanceToPoint(point) < 0) {
        continue;
      }
      final hitObjectId = hit.object?.userData['objectId'] as String?;
      final identity = hitObjectId == null ? null : _identityByObjectId[hitObjectId];
      widget.onObjectSelected!(identity);
      return;
    }
    widget.onObjectSelected!(null);
  }

  /// WO094 — [OrbitControls] 없이 직접 구면좌표(target 기준 거리/방위각
  /// azimuth/고도각 polar)로 카메라를 둔다. polar는 0(정수직 위)~π
  /// (정수직 아래) 전 구간을 허용하고 azimuth는 완전히 무제한이라(§5
  /// "회전 방향 제한 때문에 특정 면을 볼 수 없는 문제 금지"), 사용자가
  /// 못 보는 각도가 인위적으로 생기지 않는다.
  void _updateCameraFromOrbit() {
    final camera = _threeJs.camera;
    final sinPhi = math.sin(_orbitPolar);
    final cosPhi = math.cos(_orbitPolar);
    camera.position.setValues(
      _orbitTargetX + _orbitDistance * sinPhi * math.cos(_orbitAzimuth),
      _orbitTargetY + _orbitDistance * cosPhi,
      _orbitTargetZ + _orbitDistance * sinPhi * math.sin(_orbitAzimuth),
    );
    camera.lookAt(three.Vector3(_orbitTargetX, _orbitTargetY, _orbitTargetZ));
  }

  /// [dx]/[dy]/[dz]로 표현된 기존 카메라 시작 오프셋을 구면좌표
  /// (거리/방위각/고도각)로 되짚는다 — 시각적으로 기존과 똑같은 초기
  /// 시점을 유지하면서, 이후 회전/확대는 구면좌표 상태만 바꾸면 되게
  /// 한다.
  void _setOrbitFromOffset(double dx, double dy, double dz) {
    final r = math.sqrt(dx * dx + dy * dy + dz * dz);
    _orbitDistance = r <= 0 ? 1 : r;
    _orbitPolar = r <= 0 ? math.pi / 4 : math.acos((dy / r).clamp(-1.0, 1.0));
    _orbitAzimuth = math.atan2(dz, dx);
  }

  /// WO098 §6 — 드래그 전/후 camera position/azimuth/polar 값을 로그로
  /// 남긴다(실기 검증용 — 회전이 실제로 카메라 상태를 바꾸는지 코드
  /// 레벨에서도 확인 가능하게 한다).
  void _logOrbitDebug(String label) {
    final camera = _threeJs.camera;
    debugPrint(
      '[WO098 orbit] $label pos=(${camera.position.x.toStringAsFixed(1)}, '
      '${camera.position.y.toStringAsFixed(1)}, ${camera.position.z.toStringAsFixed(1)}) '
      'azimuth=${(_orbitAzimuth * 180 / math.pi).toStringAsFixed(1)}deg '
      'polar=${(_orbitPolar * 180 / math.pi).toStringAsFixed(1)}deg '
      'distance=${_orbitDistance.toStringAsFixed(1)}',
    );
  }

  /// §3/§5 — 좌클릭/터치 drag는 회전, 우클릭/중클릭 drag는 pan. 버튼
  /// 구분은 pointer down 시점의 [PointerEvent.buttons] 비트마스크로 한다
  /// (1=좌, 2=우, 4=중 — 터치/스타일러스는 항상 0이라 자연히 회전으로
  /// 처리된다).
  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 1) {
      _primaryPointerId = event.pointer;
      _primaryIsPan = (event.buttons & 0x02) != 0 || (event.buttons & 0x04) != 0;
      _tapDownPosition = event.localPosition;
      _possibleTap = true;
      _logOrbitDebug('drag start(buttons=${event.buttons})');
    } else {
      // 두 번째 이상 pointer(예: 두 손가락) — 더 이상 단순 tap이 아니다.
      _possibleTap = false;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final last = _activePointers[event.pointer];
    _activePointers[event.pointer] = event.localPosition;
    if (last == null) return;

    if (_tapDownPosition != null && (event.localPosition - _tapDownPosition!).distance > kTouchSlop) {
      _possibleTap = false;
    }

    if (event.pointer != _primaryPointerId) return;
    final delta = event.localPosition - last;
    if (_primaryIsPan) {
      _applyPan(delta);
    } else {
      _applyRotate(delta);
    }
  }

  void _applyRotate(Offset delta) {
    const rotateSensitivity = 0.012;
    _orbitAzimuth -= delta.dx * rotateSensitivity;
    _orbitPolar = (_orbitPolar - delta.dy * rotateSensitivity).clamp(0.001, math.pi - 0.001);
    _updateCameraFromOrbit();
  }

  /// §5 — 우/중클릭 drag pan. target을 화면 기준 좌/우(카메라의 실제
  /// right 벡터)·상/하(카메라의 실제 up 벡터)로 옮긴다 — 화면에 보이는
  /// 방향과 무관하게 항상 "드래그한 방향으로 장면이 따라온다"가
  /// 성립하도록 카메라 자세에서 매번 다시 계산한다(고정된 world축이
  /// 아님 — 그러면 위/아래를 보고 있을 때 pan 방향이 어긋난다).
  void _applyPan(Offset delta) {
    final camera = _threeJs.camera;
    final forward = three.Vector3(
      _orbitTargetX - camera.position.x,
      _orbitTargetY - camera.position.y,
      _orbitTargetZ - camera.position.z,
    );
    final forwardLen = forward.length;
    if (forwardLen < 1e-6) return;
    forward.scale(1 / forwardLen);

    final right = forward.clone().cross(three.Vector3(0, 1, 0));
    final rightLen = right.length;
    if (rightLen < 1e-6) return;
    right.scale(1 / rightLen);

    final camUp = right.clone().cross(forward);

    const panSensitivity = 0.0016;
    final panScale = _orbitDistance * panSensitivity;
    final dxWorld = -right.x * delta.dx * panScale + camUp.x * delta.dy * panScale;
    final dyWorld = -right.y * delta.dx * panScale + camUp.y * delta.dy * panScale;
    final dzWorld = -right.z * delta.dx * panScale + camUp.z * delta.dy * panScale;
    _orbitTargetX += dxWorld;
    _orbitTargetY += dyWorld;
    _orbitTargetZ += dzWorld;
    _updateCameraFromOrbit();
  }

  /// §4 — 마우스 휠 zoom. [GestureDetector]는 [PointerScrollEvent]를 아예
  /// 받지 못해(§ 필드 문서) 이전에는 구현 자체가 불가능했다 — [Listener.
  /// onPointerSignal]로만 받을 수 있다.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final zoomFactor = math.exp(event.scrollDelta.dy * 0.0015);
    _orbitDistance = (_orbitDistance * zoomFactor).clamp(_minOrbitDistance, _maxOrbitDistance);
    _updateCameraFromOrbit();
  }

  void _handlePointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer == _primaryPointerId) {
      _logOrbitDebug('drag end');
      if (_possibleTap) {
        _performTapSelection(event.localPosition);
      }
      _possibleTap = false;
      _tapDownPosition = null;
      _primaryPointerId = _activePointers.isEmpty ? null : _activePointers.keys.first;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer == _primaryPointerId) {
      _possibleTap = false;
      _tapDownPosition = null;
      _primaryPointerId = _activePointers.isEmpty ? null : _activePointers.keys.first;
    }
  }

  void _resetCamera() {
    final scene3d = widget.scene;
    final center = scene3d.center;
    final radius = scene3d.boundingRadius <= 0 ? 1000.0 : scene3d.boundingRadius;
    _orbitTargetX = center.x;
    _orbitTargetY = center.y;
    _orbitTargetZ = center.z;
    switch (widget.cameraMode) {
      case Space3DCameraMode.isometric:
        // WO099 §3 — Architectural Dollhouse 기본 시점. 기존 45°
        // 고전적 isometric 각도는 벽 높이가 근처 방 내부를 가려 "회색
        // CAD extrusion"처럼 보이는 원인 중 하나였다(§4 벽 재질의
        // [three.BackSide] 전환과 함께, 시점 자체도 참고 이미지처럼 더
        // 위에서 내려다보는 각도(수평선 기준 약 61°)로 바꾼다 — 전체
        // 평면이 한 화면에 들어오고 바닥이 가장 중요한 시각 요소가
        // 되도록. 회전을 시작하면(§ _handleScaleUpdate류) 이 각도에
        // 고정되지 않고 자유 회전하며, [화면 맞춤]을 누르면 이 기본값
        // 으로 복귀한다(_resetCamera 자체가 그 복귀 동작이다).
        final distance = radius * 2.6;
        _setOrbitFromOffset(distance * 0.34, distance * 0.88, distance * 0.34);
      case Space3DCameraMode.perspective:
        // WO092 §6 — 3D 투시: 같은 scene을 사람 눈높이에 가까운 낮은
        // 위치·좁은 반경에서 보는 초기 시점으로만 바꾼다(카메라
        // 시작점만 다르고 이후 자유 회전/확대는 동일).
        final distance = radius * 1.4;
        _setOrbitFromOffset(distance * 0.85, radius * 0.22 + 1600, distance * 0.85);
    }
    _updateCameraFromOrbit();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: const Color(0xFFEFF2F5))),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            onPointerCancel: _handlePointerCancel,
            onPointerSignal: _handlePointerSignal,
            child: _threeJs.build(),
          ),
        ),
        if (widget.onExitTo2D != null)
          Positioned(
            left: 12,
            top: 12,
            child: _IconLabelButtonGpu(
              icon: Icons.arrow_back_rounded,
              label: '2D 평면도로 돌아가기',
              onTap: widget.onExitTo2D!,
            ),
          ),
        Positioned(
          right: 12,
          top: 12,
          child: Row(
            children: [
              if (widget.onToggleFullscreen != null)
                _IconLabelButtonGpu(
                  icon: widget.isFullscreen ? Icons.close_rounded : Icons.fullscreen_rounded,
                  label: widget.isFullscreen ? '닫기' : '전체 화면',
                  onTap: widget.onToggleFullscreen!,
                ),
              const SizedBox(width: 8),
              _IconLabelButtonGpu(
                icon: Icons.center_focus_strong_rounded,
                label: '화면 맞춤',
                onTap: () => setState(_resetCamera),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconLabelButtonGpu extends StatelessWidget {
  const _IconLabelButtonGpu({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: SpaceShiftColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: SpaceShiftColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SpaceShiftColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
