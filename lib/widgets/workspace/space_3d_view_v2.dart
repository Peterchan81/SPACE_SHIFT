import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../models/space_scene_v2.dart';
import '../../theme/space_shift_colors.dart';
// 카메라 투영 수학(near/far plane, view*projection 행렬, 화면 투영)과
// preset 각도/pitch 한계는 순수 함수/상수라 [SpaceScene](V1) 타입에
// 의존하지 않는다 — V2가 "기존 3D 구현에 patch를 추가"하는 게 아니라,
// 이미 검증된 카메라 수학 유틸리티 하나를 공유하는 것뿐이다(카메라
// 수학을 두 번 구현하면 그 자체로 새 버그의 원인이 된다). V2 렌더러
// 본체(_Space3DPainterV2 — 실제 depth-buffer 래스터라이저)는 V1과
// 완전히 독립적으로 새로 작성한다.
import 'space_3d_view.dart'
    show
        ViewPreset,
        ViewPresetX,
        buildViewProjectionMatrix,
        kMaxCameraPitch,
        kMinCameraPitch,
        nearPlaneDistanceFor;

/// SpaceScene V2 렌더러 — NOMPASS V2 WO(13/14/15번): 기존 렌더러는
/// z-buffer 없는 painter's algorithm(삼각형 centroid 거리 정렬)만 써서,
/// 두께가 있는 벽의 안쪽/바깥쪽 면처럼 깊이가 거의 같은 면들의 그리기
/// 순서가 자주 틀렸다(벽이 찢어져 보이는 근본 원인 중 하나). 이번
/// pipeline은 조사 결과에 따라 다음 순서로 렌더러를 결정했다:
///
/// A. Windows/Android/Web 어디서나 추가 플랫폼 설정 없이 쓸 수 있는
///    실제 GPU depth-buffer(Flutter Scene/Impeller 3D, flutter_gpu 등) —
///    이번 시점 기준 전부 "early access"/Impeller 전용/Web 미지원이라
///    세 플랫폼 동시 지원이라는 이 프로젝트의 최우선 요구사항(WO 10번)을
///    충족하지 못한다. 채택하지 않는다.
/// B. 기존 dependency 추가 없는 3D 패키지 — 검증된 성숙한 순수 Dart/
///    Flutter 전용 3D 렌더러가 없다(대부분 결국 GL/Impeller 바인딩에
///    의존). 채택하지 않는다.
/// C. 새 dependency 추가 — 위 A/B가 이미 세 플랫폼 동시 지원을 만족하지
///    못하는 상태에서 무거운 3D 엔진을 새로 들이는 위험/유지보수 비용이
///    이번 범위(정확한 CAD shell 검증)에 비해 과도하다.
///
/// → 그래서 WO 15번이 제시한 대안대로 CPU 측 depth 처리를 택하되,
/// 픽셀 단위 z-buffer(해상도당 픽셀 수 × 삼각형 수 비용) 대신 "coarse
/// raster"(성긴 tile 격자, WO 15번 명시적 예시)를 쓴다 — 각 tile
/// 중심에서 실제 원근-보정 깊이(1/w interpolation)를 비교해 tile 단위로
/// 진짜 depth test를 수행한다. Canvas.drawRect만 쓰므로 dart:ui의 비동기
/// 이미지 디코드 없이 [CustomPainter.paint] 안에서 완전히 동기적으로
/// 끝난다 — painter's algorithm의 "정렬 실패" 버그 클래스 자체가 없어진다
/// (겹치는 두 면 중 tile마다 실제로 더 가까운 쪽이 항상 이긴다).
class Space3DViewV2 extends StatefulWidget {
  const Space3DViewV2({
    super.key,
    required this.scene,
    this.isFullscreenRoute = false,
    this.onExitTo2D,
  });

  final SpaceSceneV2 scene;
  final bool isFullscreenRoute;
  final VoidCallback? onExitTo2D;

  @override
  State<Space3DViewV2> createState() => _Space3DViewV2State();
}

class _Space3DViewV2State extends State<Space3DViewV2> {
  late double _yaw;
  late double _pitch;
  late double _distance;
  late vm.Vector3 _target;

  double? _dragScaleStart;
  Offset? _lastFocalPoint;
  bool _panningWithMouse = false;

  @override
  void initState() {
    super.initState();
    _fitToScene();
  }

  @override
  void didUpdateWidget(covariant Space3DViewV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scene, widget.scene)) _fitToScene();
  }

  void _fitToScene() {
    final scene = widget.scene;
    _target = scene.center;
    final radius = scene.boundingRadius <= 0 ? 1000.0 : scene.boundingRadius;
    _distance = radius * 2.6;
    _yaw = math.pi / 4;
    _pitch = math.atan(1 / math.sqrt2);
  }

  vm.Vector3 get _eye {
    final cp = math.cos(_pitch);
    return _target +
        vm.Vector3(
          _distance * cp * math.sin(_yaw),
          _distance * math.sin(_pitch),
          _distance * cp * math.cos(_yaw),
        );
  }

  void _applyPreset(ViewPreset preset) {
    final (yaw, pitch) = preset.angles;
    setState(() {
      _yaw = yaw;
      _pitch = pitch;
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kSecondaryMouseButton) != 0) {
      _panningWithMouse = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _panningWithMouse = false;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _dragScaleStart = _distance;
    _lastFocalPoint = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final last = _lastFocalPoint;
    final delta = last == null ? Offset.zero : details.focalPoint - last;
    _lastFocalPoint = details.focalPoint;

    setState(() {
      if (details.pointerCount >= 2) {
        final start = _dragScaleStart;
        if (start != null && details.scale > 0) {
          _distance = (start / details.scale).clamp(
            widget.scene.boundingRadius * 0.3 + 1,
            widget.scene.boundingRadius * 12 + 5000,
          );
        }
        _panBy(delta);
      } else if (_panningWithMouse) {
        _panBy(delta);
      } else {
        _yaw -= delta.dx * 0.01;
        _pitch = (_pitch + delta.dy * 0.01).clamp(
          kMinCameraPitch,
          kMaxCameraPitch,
        );
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _dragScaleStart = null;
    _lastFocalPoint = null;
  }

  void _panBy(Offset screenDelta) {
    final forward = (_target - _eye).normalized();
    final worldUp = vm.Vector3(0, 1, 0);
    final right = forward.cross(worldUp).normalized();
    final up = right.cross(forward).normalized();
    final panScale = _distance * 0.0015;
    _target -= right * (screenDelta.dx * panScale);
    _target += up * (screenDelta.dy * panScale);
  }

  void _onPointerScroll(PointerScrollEvent event) {
    setState(() {
      final factor = math.exp(event.scrollDelta.dy * 0.0012);
      _distance = (_distance * factor).clamp(
        widget.scene.boundingRadius * 0.3 + 1,
        widget.scene.boundingRadius * 12 + 5000,
      );
    });
  }

  Future<void> _enterFullscreen() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: _FullscreenSpace3DPageV2(scene: widget.scene),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) _onPointerScroll(event);
            },
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: CustomPaint(
                painter: _Space3DPainterV2(
                  scene: widget.scene,
                  eye: _eye,
                  target: _target,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          right: 12,
          child: _ViewPresetBarV2(onSelected: _applyPreset),
        ),
        if (widget.onExitTo2D != null)
          Positioned(
            left: 12,
            top: 12,
            child: _IconLabelButtonV2(
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
                _IconLabelButtonV2(
                  icon: Icons.fullscreen_rounded,
                  label: '전체 화면',
                  onTap: _enterFullscreen,
                ),
                const SizedBox(width: 8),
              ],
              _IconLabelButtonV2(
                icon: Icons.center_focus_strong_rounded,
                label: '화면 맞춤',
                onTap: () => setState(_fitToScene),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FullscreenSpace3DPageV2 extends StatelessWidget {
  const _FullscreenSpace3DPageV2({required this.scene});

  final SpaceSceneV2 scene;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Space3DViewV2(scene: scene, isFullscreenRoute: true),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: _IconLabelButtonV2(
                  icon: Icons.close_rounded,
                  label: '닫기(ESC)',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconLabelButtonV2 extends StatelessWidget {
  const _IconLabelButtonV2({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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

class _ViewPresetBarV2 extends StatelessWidget {
  const _ViewPresetBarV2({required this.onSelected});

  final ValueChanged<ViewPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SpaceShiftColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final preset in ViewPreset.values)
                InkWell(
                  onTap: () => onSelected(preset),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Text(
                      preset.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 실제 depth test를 수행하는 coarse tile z-buffer 래스터라이저 — 핵심
/// 수학(격자 크기 계산, 원근-보정 depth 보간)을 순수 함수로 빼서
/// [_Space3DPainterV2] 없이도 단위 테스트할 수 있게 한다.
const int kTileGridTargetCols = 160;

(int cols, int rows, double tileSize) tileGridSizeFor(Size size) {
  final tileSize = math.max(2.0, size.width / kTileGridTargetCols);
  final cols = math.max(1, (size.width / tileSize).ceil());
  final rows = math.max(1, (size.height / tileSize).ceil());
  return (cols, rows, tileSize);
}

/// 화면 좌표 [p]가 화면 공간 삼각형(sa/sb/sc, 각 정점의 원근-보정
/// 역깊이 invWa/invWb/invWc와 짝) 안에 있으면 그 지점의 보간된 1/w를
/// 돌려준다(클수록 카메라에 가깝다 — depth buffer 비교 기준). 밖이면
/// null. 화면 공간에서 1/w를 직접 barycentric 보간하는 것은 원근
/// 투영에서도 정확한 표준 기법이다 — [_Space3DPainterV2]와 테스트가
/// 정확히 같은 판정을 쓰도록 공개 함수로 뺐다(WO 13/14/15번 — "실제
/// depth-buffer 기반" 렌더링의 핵심 수학).
double? barycentricInvDepthAt(
  Offset p,
  Offset sa,
  Offset sb,
  Offset sc,
  double invWa,
  double invWb,
  double invWc,
) {
  final denom =
      (sb.dy - sc.dy) * (sa.dx - sc.dx) + (sc.dx - sb.dx) * (sa.dy - sc.dy);
  if (denom.abs() < 1e-9) return null;
  final w0 =
      ((sb.dy - sc.dy) * (p.dx - sc.dx) + (sc.dx - sb.dx) * (p.dy - sc.dy)) /
      denom;
  final w1 =
      ((sc.dy - sa.dy) * (p.dx - sc.dx) + (sa.dx - sc.dx) * (p.dy - sc.dy)) /
      denom;
  final w2 = 1 - w0 - w1;
  if (w0 < -1e-6 || w1 < -1e-6 || w2 < -1e-6) return null;
  return w0 * invWa + w1 * invWb + w2 * invWc;
}

class _Space3DPainterV2 extends CustomPainter {
  _Space3DPainterV2({
    required this.scene,
    required this.eye,
    required this.target,
  });

  final SpaceSceneV2 scene;
  final vm.Vector3 eye;
  final vm.Vector3 target;

  static final vm.Vector3 _lightDir = vm.Vector3(-0.4, 0.85, 0.3).normalized();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEFF2F5),
    );
    if (scene.isEmpty || size.width <= 0 || size.height <= 0) return;

    final viewProj = buildViewProjectionMatrix(
      eye: eye,
      target: target,
      boundingRadius: scene.boundingRadius,
      aspect: size.width / size.height,
    );
    final near = nearPlaneDistanceFor(scene.boundingRadius);
    final forward = (target - eye).normalized();
    bool behindNear(vm.Vector3 v) => (v - eye).dot(forward) <= near;

    final (cols, rows, tileSize) = tileGridSizeFor(size);
    final depth = Float64List(cols * rows)..fillRange(0, cols * rows, -1);
    final colors = List<Color?>.filled(cols * rows, null);

    for (final tri in scene.triangles) {
      if (behindNear(tri.a) || behindNear(tri.b) || behindNear(tri.c)) continue;
      final toCamera = eye - tri.centroid;
      if (toCamera.length2 == 0) continue;
      if (tri.normal.dot(toCamera) <= 0) continue; // backface culling.

      final ca = viewProj.transform(vm.Vector4(tri.a.x, tri.a.y, tri.a.z, 1));
      final cb = viewProj.transform(vm.Vector4(tri.b.x, tri.b.y, tri.b.z, 1));
      final cc = viewProj.transform(vm.Vector4(tri.c.x, tri.c.y, tri.c.z, 1));
      if (ca.w <= 0.0001 || cb.w <= 0.0001 || cc.w <= 0.0001) continue;
      final invWa = 1 / ca.w, invWb = 1 / cb.w, invWc = 1 / cc.w;
      final sax = (ca.x * invWa * 0.5 + 0.5) * size.width;
      final say = (1 - (ca.y * invWa * 0.5 + 0.5)) * size.height;
      final sbx = (cb.x * invWb * 0.5 + 0.5) * size.width;
      final sby = (1 - (cb.y * invWb * 0.5 + 0.5)) * size.height;
      final scx = (cc.x * invWc * 0.5 + 0.5) * size.width;
      final scy = (1 - (cc.y * invWc * 0.5 + 0.5)) * size.height;
      if (!sax.isFinite ||
          !say.isFinite ||
          !sbx.isFinite ||
          !sby.isFinite ||
          !scx.isFinite ||
          !scy.isFinite) {
        continue;
      }

      final shade = (0.35 + 0.65 * tri.normal.dot(_lightDir).clamp(0.0, 1.0))
          .clamp(0.0, 1.0);
      final shadedColor = Color.lerp(Colors.black, tri.color, shade)!;

      final minTx = math.max(
        0,
        (math.min(sax, math.min(sbx, scx)) / tileSize).floor(),
      );
      final maxTx = math.min(
        cols - 1,
        (math.max(sax, math.max(sbx, scx)) / tileSize).ceil(),
      );
      final minTy = math.max(
        0,
        (math.min(say, math.min(sby, scy)) / tileSize).floor(),
      );
      final maxTy = math.min(
        rows - 1,
        (math.max(say, math.max(sby, scy)) / tileSize).ceil(),
      );
      if (minTx > maxTx || minTy > maxTy) continue;

      final sa = Offset(sax, say);
      final sb = Offset(sbx, sby);
      final sc = Offset(scx, scy);

      for (var ty = minTy; ty <= maxTy; ty++) {
        final py = (ty + 0.5) * tileSize;
        final rowOffset = ty * cols;
        for (var tx = minTx; tx <= maxTx; tx++) {
          final px = (tx + 0.5) * tileSize;
          final depthVal = barycentricInvDepthAt(
            Offset(px, py),
            sa,
            sb,
            sc,
            invWa,
            invWb,
            invWc,
          );
          if (depthVal == null) continue;
          final idx = rowOffset + tx;
          if (depthVal > depth[idx]) {
            depth[idx] = depthVal;
            colors[idx] = shadedColor;
          }
        }
      }
    }

    final paint = Paint()..style = PaintingStyle.fill;
    for (var ty = 0; ty < rows; ty++) {
      final rowOffset = ty * cols;
      for (var tx = 0; tx < cols; tx++) {
        final c = colors[rowOffset + tx];
        if (c == null) continue;
        paint.color = c;
        canvas.drawRect(
          Rect.fromLTWH(
            tx * tileSize,
            ty * tileSize,
            tileSize + 0.5,
            tileSize + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Space3DPainterV2 oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.eye != eye ||
        oldDelegate.target != target;
  }
}
