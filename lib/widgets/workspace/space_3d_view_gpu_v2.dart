import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import '../../models/space_scene_v2.dart';
import '../../theme/space_shift_colors.dart';

/// SpaceScene V2 GPU 렌더러 — Windows 실기 재조사(3D) 결론에 따른
/// renderer architecture 교체. CPU coarse-tile z-buffer([space_3d_view_v2.dart],
/// 삭제하지 않고 보존)는 실기에서 벽/바닥 경계가 심하게 계단화된 큰
/// 사각 block으로 보였다 — tile 해상도를 올려서 증상만 가리는 대신,
/// 실제 GPU 삼각형 rasterization + 실제 depth buffer를 쓰는 `three_js`
/// (ANGLE 기반 네이티브 렌더러, Windows/Android/Web 모두 stable
/// Flutter SDK에서 동작, MIT 라이선스)로 렌더러 자체를 교체한다.
///
/// [SpaceSceneV2](mesh 데이터, mm 단위 world 좌표)는 그대로 재사용한다 —
/// 이번 교체는 오직 "그 데이터를 화면에 어떻게 그리는가"만 바꾼다.
class Space3DViewGpuV2 extends StatefulWidget {
  const Space3DViewGpuV2({
    super.key,
    required this.scene,
    this.isFullscreenRoute = false,
    this.onExitTo2D,
  });

  final SpaceSceneV2 scene;
  final bool isFullscreenRoute;
  final VoidCallback? onExitTo2D;

  @override
  State<Space3DViewGpuV2> createState() => _Space3DViewGpuV2State();
}

class _Space3DViewGpuV2State extends State<Space3DViewGpuV2> {
  late three.ThreeJS _threeJs;
  three.OrbitControls? _controls;

  @override
  void initState() {
    super.initState();
    _threeJs = three.ThreeJS(onSetupComplete: () {}, setup: _setup);
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

    _buildMeshes(scene3d);

    _fitCamera();

    _controls = three.OrbitControls(_threeJs.camera, _threeJs.globalKey)
      ..enableDamping = true
      ..dampingFactor = 0.12
      ..minDistance = radius * 0.3 + 1
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

    _threeJs.addAnimationEvent((dt) => _controls?.update());
  }

  void _buildMeshes(SpaceSceneV2 scene3d) {
    // 색상별로 삼각형을 묶어 mesh/material 개수를 최소화한다(WO — 이번
    // 범위는 재질 시스템이 아니라 벽/바닥 2~3가지 고정 색뿐이라 이
    // 정도로 충분하다. MASTER 단계(재질/색상 편집)에서 객체별 mesh로
    // 다시 나눌 수 있도록 [SpaceObjectIdentityV2]는 이미 준비돼 있다).
    final byColor = <int, List<SpaceTriangleV2>>{};
    for (final wall in scene3d.wallMeshes) {
      final hex = _colorToHex(wall.identity.color ?? const Color(0xFFC9C2B4));
      byColor.putIfAbsent(hex, () => []).addAll(wall.triangles);
    }
    for (final floor in scene3d.floorMeshes) {
      final hex = _colorToHex(floor.identity.color ?? const Color(0xFFD9CBB2));
      byColor.putIfAbsent(hex, () => []).addAll(floor.triangles);
    }
    for (final entry in byColor.entries) {
      final mesh = _buildMeshForTriangles(entry.value, entry.key);
      if (mesh != null) _threeJs.scene.add(mesh);
    }
  }

  three.Mesh? _buildMeshForTriangles(List<SpaceTriangleV2> triangles, int colorHex) {
    if (triangles.isEmpty) return null;
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

    final material = three.MeshLambertMaterial({
      three.MaterialProperty.color: colorHex,
      three.MaterialProperty.side: three.DoubleSide,
    });
    return three.Mesh(geometry, material);
  }

  int _colorToHex(Color color) {
    final r = (color.r * 255).round() & 0xFF;
    final g = (color.g * 255).round() & 0xFF;
    final b = (color.b * 255).round() & 0xFF;
    return (r << 16) | (g << 8) | b;
  }

  void _fitCamera() {
    final scene3d = widget.scene;
    final center = scene3d.center;
    final radius = scene3d.boundingRadius <= 0 ? 1000.0 : scene3d.boundingRadius;
    final distance = radius * 2.6;
    // 고전적인 isometric에 가까운 기본 시점 — V1/V2 CPU 렌더러와 동일한
    // 각도(첫 진입 시 동일한 느낌을 주기 위해).
    final camera = _threeJs.camera;
    camera.position.setValues(
      center.x + distance * 0.5,
      center.y + distance * 0.7,
      center.z + distance * 0.5,
    );
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
          child: _FullscreenSpace3DPageGpu(scene: widget.scene),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: const Color(0xFFEFF2F5))),
        Positioned.fill(child: _threeJs.build()),
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
                onTap: () => setState(_fitCamera),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FullscreenSpace3DPageGpu extends StatelessWidget {
  const _FullscreenSpace3DPageGpu({required this.scene});

  final SpaceSceneV2 scene;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Space3DViewGpuV2(scene: scene, isFullscreenRoute: true)),
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
