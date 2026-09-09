import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import '../../models/space_scene_v2.dart';
import '../../services/iso_cutaway.dart';
import '../../theme/space_shift_colors.dart';

/// WO092 §6 — 3D 아이소/3D 투시는 같은 실시간 scene을 쓰고 카메라
/// 배치만 다르다. [isometric]은 기존과 같은 "위에서 내려다보는" 초기
/// 시점, [perspective]는 방 안 눈높이에서 보는 초기 시점이다 — 둘 다
/// [OrbitControls]로 자유롭게 회전/확대할 수 있어 사용자가 두 모드를
/// 완전히 다른 화면으로 느끼지 않는다(같은 재질 변경이 양쪽에 그대로
/// 반영된다).
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
/// WO093 — "3D 아이소 Cutaway/Dollhouse 표현 수정": [Space3DCameraMode.isometric]
/// 에서는 일반 3D처럼 벽을 전부 세워두지 않는다. 매 프레임 카메라
/// 위치를 기준으로 "카메라 → 각 방 중심" 시선을 가로막는 벽을
/// [_applyIsoCutaway]가 찾아 숨겨서, 확대/회전 중에도 지금 보고 있는
/// 방의 내부가 항상 보이게 한다(실기 확인된 문제: 확대하면 앞쪽 벽에
/// 가려 작은 방 내부가 안 보임 — 카메라 문제가 아니라 렌더링 방식
/// 문제였다). [Space3DCameraMode.perspective]는 이 cutaway를 전혀 타지
/// 않고 기존처럼 모든 벽을 그대로 보여준다.
class Space3DViewGpuV2 extends StatefulWidget {
  const Space3DViewGpuV2({
    super.key,
    required this.scene,
    this.isFullscreenRoute = false,
    this.onExitTo2D,
    this.cameraMode = Space3DCameraMode.isometric,
    this.selectedObjectId,
    this.onObjectSelected,
  });

  final SpaceSceneV2 scene;
  final bool isFullscreenRoute;
  final VoidCallback? onExitTo2D;
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
  three.OrbitControls? _controls;
  final Map<String, three.Mesh> _meshByObjectId = {};
  final Map<String, SpaceObjectIdentityV2> _identityByObjectId = {};
  String? _appliedHighlightId;

  /// WO093 — 아이소 cutaway/dollhouse 판정에 쓰는 벽 중심선(XZ 평면,
  /// mm) 목록. 실제 mesh geometry가 아니라 [SpaceWallMeshV2.startMm]/
  /// [endMm]만 쓰는 이유는 "가장 단순하고 안정적인 방법"(WO 지침)이라 —
  /// 벽 두께까지 반영한 정확한 폴리곤 대신 중심선 하나로 충분히
  /// 안정적으로 판단된다.
  final List<WallSegmentXZ> _wallSegmentsXZ = [];

  /// WO093 — "카메라 → 이 지점이 막혀 있으면 그 사이 벽을 숨긴다"의
  /// 목적지 목록. 방(바닥) 하나당 하나씩, 실제로 바닥이 만들어진 방만
  /// 대상으로 한다(삼각분할 실패 등으로 제외된 방은 애초에 안 보이는
  /// 대상이라 판정에서도 제외).
  final List<(double, double)> _roomCentroidsXZ = [];

  @override
  void initState() {
    super.initState();
    _threeJs = three.ThreeJS(onSetupComplete: () {}, setup: _setup);
  }

  @override
  void didUpdateWidget(covariant Space3DViewGpuV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene != widget.scene) {
      _rebuildMeshes(widget.scene);
      _applyHighlight();
      _applyIsoCutaway();
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
      _applyIsoCutaway();
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

    _threeJs.camera = three.PerspectiveCamera(
      45,
      _threeJs.width / _threeJs.height,
      radius * 0.01 + 1,
      farPlane,
    );
    _threeJs.scene = three.Scene();

    _threeJs.scene.add(three.AmbientLight(0xffffff, 0.55));
    final dirLight = three.DirectionalLight(0xffffff, 0.75);
    dirLight.position.setValues(-radius * 0.6, radius * 1.4, radius * 0.5);
    _threeJs.scene.add(dirLight);
    final fillLight = three.DirectionalLight(0xffffff, 0.25);
    fillLight.position.setValues(radius * 0.8, radius * 0.6, -radius * 0.6);
    _threeJs.scene.add(fillLight);

    _rebuildMeshes(scene3d);
    _applyHighlight();

    _resetCamera();
    _applyIsoCutaway();

    _controls = three.OrbitControls(_threeJs.camera, _threeJs.globalKey)
      ..enableDamping = true
      ..dampingFactor = 0.12
      ..minDistance = radius * 0.05 + 1
      ..maxDistance = radius * 12 + 5000
      ..target.setValues(scene3d.center.x, scene3d.center.y, scene3d.center.z)
      ..update();

    _threeJs.windowResizeUpdate = (Size newSize) {
      final camera = _threeJs.camera;
      if (camera is three.PerspectiveCamera && newSize.height > 0) {
        camera.aspect = newSize.width / newSize.height;
        camera.updateProjectionMatrix();
      }
    };

    _threeJs.addAnimationEvent((dt) {
      _controls?.update();
      // WO093 §5 — 회전/확대(damping 관성 포함)로 카메라 위치가 매
      // 프레임 바뀔 수 있어, cutaway 판정도 매 프레임 다시 계산한다.
      // 벽/방 개수가 이 앱 규모(수십 개 이내)라 매 프레임 재계산해도
      // 비용이 미미하다.
      _applyIsoCutaway();
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
    _wallSegmentsXZ.clear();
    _roomCentroidsXZ.clear();

    for (final wall in scene3d.wallMeshes) {
      _addObjectMesh(wall.identity, wall.triangles, doubleSided: true);
      _wallSegmentsXZ.add((
        objectId: wall.identity.objectId,
        sx: wall.startMm.x,
        sz: wall.startMm.z,
        ex: wall.endMm.x,
        ez: wall.endMm.z,
        topY: wall.identity.dimensions?.heightMm ?? 0,
      ));
    }
    for (final floor in scene3d.floorMeshes) {
      _addObjectMesh(floor.identity, floor.triangles, doubleSided: true);
      if (floor.polygonMm.isNotEmpty) {
        var cx = 0.0, cz = 0.0;
        for (final p in floor.polygonMm) {
          cx += p.x;
          cz += p.z;
        }
        _roomCentroidsXZ.add((cx / floor.polygonMm.length, cz / floor.polygonMm.length));
      }
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
  }

  void _addObjectMesh(
    SpaceObjectIdentityV2 identity,
    List<SpaceTriangleV2> triangles, {
    required bool doubleSided,
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
    final material = three.MeshLambertMaterial({
      three.MaterialProperty.color: colorHex,
      three.MaterialProperty.side: doubleSided ? three.DoubleSide : three.FrontSide,
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

  /// WO093 — "3D 아이소 Cutaway/Dollhouse 표현 수정": 아이소 모드에서
  /// 카메라와 각 방(바닥 중심) 사이를 가로막는 벽을 모두 찾아 숨긴다.
  /// 매 프레임 카메라 위치 기준으로 다시 계산해서, 회전/확대해도(§5)
  /// "지금 실제로 가로막는 벽"만 정확히 숨겨진다 — 고정된 "바깥쪽 벽
  /// 2개"를 미리 정해 숨기는 방식이 아니라, 모든 방을 대상으로 매번
  /// 판정하기 때문에 특정 작은 방을 확대해도(§2 "확대해도 방 내부가
  /// 계속 보여야 함") 그 방을 가리는 벽(외벽이든 내벽이든)이 그때그때
  /// 숨겨진다. 3D 투시 모드([Space3DCameraMode.perspective])는 기존
  /// 방식을 그대로 유지해야 하므로(§1) 이 함수를 타지 않고 항상 모든
  /// 벽을 보여준다.
  ///
  /// 실제 판정 로직은 [computeIsoCutawayHiddenWallIds](iso_cutaway.dart)에
  /// 있다 — 카메라 높이까지 반영한 3D 시선 판정이라(단순 XZ 평면
  /// 투영만으로는 "멀리서 내려다볼 때 낮은 칸막이벽 때문에 먼 방까지
  /// 숨겨지는" 오판이 실제로 발생했다), 위젯 없이도 단위 테스트로
  /// 검증할 수 있다.
  void _applyIsoCutaway() {
    if (widget.cameraMode != Space3DCameraMode.isometric) {
      for (final segment in _wallSegmentsXZ) {
        _meshByObjectId[segment.objectId]?.visible = true;
      }
      return;
    }
    final hidden = computeIsoCutawayHiddenWallIds(
      cameraX: _threeJs.camera.position.x,
      cameraY: _threeJs.camera.position.y,
      cameraZ: _threeJs.camera.position.z,
      wallSegments: _wallSegmentsXZ,
      roomCentroidsXZ: _roomCentroidsXZ,
    );
    for (final segment in _wallSegmentsXZ) {
      _meshByObjectId[segment.objectId]?.visible = !hidden.contains(segment.objectId);
    }
  }

  /// WO092 §5 — 화면을 탭한 지점으로 실제 ray를 쏴서 부딪힌 mesh를
  /// 찾는다. [OrbitControls]는 raw pointer Listener로 회전/확대를
  /// 처리하므로(gesture arena를 타지 않음) 이 [GestureDetector]의 탭
  /// 인식과 서로 방해하지 않는다 — 드래그(회전)에는 탭이 발생하지
  /// 않고, 제자리 탭에는 회전이 사실상 일어나지 않는다.
  void _handleTapUp(TapUpDetails details) {
    if (widget.onObjectSelected == null) return;
    final width = _threeJs.width;
    final height = _threeJs.height;
    if (width <= 0 || height <= 0) return;
    final ndcX = (details.localPosition.dx / width) * 2 - 1;
    final ndcY = -(details.localPosition.dy / height) * 2 + 1;

    final raycaster = three.Raycaster();
    raycaster.setFromCamera(three.Vector2(ndcX, ndcY), _threeJs.camera);
    // WO093 §4 — cutaway로 숨겨진(invisible) 벽은 화면에 보이지 않으므로
    // 탭 대상에서도 제외한다. three_js의 Raycaster는 `.visible`을 직접
    // 확인하지 않아서(원본 three.js와 달리 이 포팅에는 그 필터가 없다)
    // 걸러주지 않으면 안 보이는 벽이 선택되어 "보이는 것과 실제 선택되는
    // 것이 다른" 혼란(§4 "Cutaway 때문에 객체 선택 기능이 깨지면 안 됨")
    // 이 생긴다.
    final pickable = _meshByObjectId.values.where((m) => m.visible).toList(growable: false);
    final hits = raycaster.intersectObjects(pickable, false);
    if (hits.isEmpty) {
      widget.onObjectSelected!(null);
      return;
    }
    final hitObjectId = hits.first.object?.userData['objectId'] as String?;
    final identity = hitObjectId == null ? null : _identityByObjectId[hitObjectId];
    widget.onObjectSelected!(identity);
  }

  void _resetCamera() {
    final scene3d = widget.scene;
    final center = scene3d.center;
    final radius = scene3d.boundingRadius <= 0 ? 1000.0 : scene3d.boundingRadius;
    final camera = _threeJs.camera;
    switch (widget.cameraMode) {
      case Space3DCameraMode.isometric:
        // 고전적인 isometric에 가까운 기본 시점 — 위에서 내려다보는
        // dollhouse/cutaway 뷰(WO092 §3 "전체 공간 확인").
        final distance = radius * 2.6;
        camera.position.setValues(
          center.x + distance * 0.5,
          center.y + distance * 0.7,
          center.z + distance * 0.5,
        );
      case Space3DCameraMode.perspective:
        // WO092 §6 — 3D 투시: 같은 scene을 사람 눈높이에 가까운 낮은
        // 위치·좁은 반경에서 보는 초기 시점으로만 바꾼다(카메라
        // 시작점만 다르고 이후 자유 회전/확대는 동일).
        final distance = radius * 1.4;
        camera.position.setValues(
          center.x + distance * 0.85,
          center.y + radius * 0.22 + 1600,
          center.z + distance * 0.85,
        );
    }
    camera.lookAt(three.Vector3(center.x, center.y, center.z));
    _controls?.target.setValues(center.x, center.y, center.z);
    _controls?.update();
  }

  Future<void> _enterFullscreen() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: _FullscreenSpace3DPageGpu(
            scene: widget.scene,
            cameraMode: widget.cameraMode,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: const Color(0xFFEFF2F5))),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _handleTapUp,
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
              if (!widget.isFullscreenRoute) ...[
                _IconLabelButtonGpu(
                  icon: Icons.fullscreen_rounded,
                  label: '전체 화면',
                  onTap: _enterFullscreen,
                ),
                const SizedBox(width: 8),
              ],
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

class _FullscreenSpace3DPageGpu extends StatelessWidget {
  const _FullscreenSpace3DPageGpu({required this.scene, required this.cameraMode});

  final SpaceSceneV2 scene;
  final Space3DCameraMode cameraMode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Space3DViewGpuV2(
              scene: scene,
              cameraMode: cameraMode,
              isFullscreenRoute: true,
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: _IconLabelButtonGpu(
              icon: Icons.close_rounded,
              label: '닫기',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
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
