import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../models/space_scene.dart';
import '../../theme/space_shift_colors.dart';

/// 실제로 조작 가능한 3D 아이소 뷰 — 정적 이미지/pre-render가 아니라
/// [SpaceScene]의 삼각형을 매 프레임 실제로 투영해서 그린다(WO 12번:
/// 회전/확대/축소/pan/화면 맞춤).
///
/// 외부 3D 엔진(flutter_gl/three_dart 등 네이티브 GL 바인딩) 없이,
/// [CustomPainter] 위에서 원근 투영 + 화가 알고리즘(깊이 정렬)으로 직접
/// 그리는 소프트웨어 래스터라이저다 — Windows/Android/Web 어디서도 추가
/// 플랫폼 설정 없이 완전히 동일하게 동작한다(WO 10번 1~3 조건).
class Space3DView extends StatefulWidget {
  const Space3DView({super.key, required this.scene});

  final SpaceScene scene;

  @override
  State<Space3DView> createState() => _Space3DViewState();
}

class _Space3DViewState extends State<Space3DView> {
  static const double _minPitch = 0.08;
  static const double _maxPitch = math.pi / 2 - 0.08;

  late double _yaw;
  late double _pitch;
  late double _distance;
  late vm.Vector3 _target;

  double? _dragScaleStart;
  Offset? _lastFocalPoint;

  @override
  void initState() {
    super.initState();
    _fitToScene();
  }

  @override
  void didUpdateWidget(covariant Space3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scene, widget.scene)) _fitToScene();
  }

  void _fitToScene() {
    final scene = widget.scene;
    _target = scene.center;
    final radius = scene.boundingRadius <= 0 ? 1000.0 : scene.boundingRadius;
    _distance = radius * 2.6;
    // 고전적인 isometric에 가까운 기본 시점 — 공간 전체를 한눈에 이해하기
    // 쉬운 위에서 비스듬히 내려다보는 각도(WO 12번 "isometric-like view").
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
        // 두 손가락 — 확대/축소 + pan.
        final start = _dragScaleStart;
        if (start != null && details.scale > 0) {
          _distance = (start / details.scale).clamp(
            widget.scene.boundingRadius * 0.3 + 1,
            widget.scene.boundingRadius * 12 + 5000,
          );
        }
        _panBy(delta);
      } else {
        // 한 손가락 — 궤도 회전.
        _yaw -= delta.dx * 0.01;
        _pitch = (_pitch + delta.dy * 0.01).clamp(_minPitch, _maxPitch);
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _dragScaleStart = null;
    _lastFocalPoint = null;
  }

  /// 카메라가 바라보는 방향을 기준으로 화면 이동만큼 [_target]을 옮긴다
  /// (마우스/터치로 공간 안을 이동, WO 12번 "pan 또는 적절한 공간 이동").
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) _onPointerScroll(event);
            },
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: CustomPaint(
                painter: _Space3DPainter(
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
          right: 12,
          top: 12,
          child: _FitViewButton(onTap: () => setState(_fitToScene)),
        ),
      ],
    );
  }
}

class _FitViewButton extends StatelessWidget {
  const _FitViewButton({required this.onTap});

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
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.center_focus_strong_rounded,
                size: 16,
                color: SpaceShiftColors.textSecondary,
              ),
              SizedBox(width: 6),
              Text(
                '화면 맞춤',
                style: TextStyle(
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

class _Space3DPainter extends CustomPainter {
  _Space3DPainter({
    required this.scene,
    required this.eye,
    required this.target,
  });

  final SpaceScene scene;
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

    final radius = scene.boundingRadius <= 0 ? 1000.0 : scene.boundingRadius;
    final near = math.max(1.0, radius * 0.01);
    final far = radius * 20 + (eye - target).length * 2;
    final aspect = size.width / size.height;
    final proj = vm.makePerspectiveMatrix(
      45 * math.pi / 180,
      aspect,
      near,
      far,
    );
    final view = vm.makeViewMatrix(eye, target, vm.Vector3(0, 1, 0));
    final viewProj = proj * view;

    Offset? project(vm.Vector3 v) {
      final clip = viewProj.transform(vm.Vector4(v.x, v.y, v.z, 1));
      if (clip.w <= 0.0001) return null;
      final ndcX = clip.x / clip.w;
      final ndcY = clip.y / clip.w;
      return Offset(
        (ndcX * 0.5 + 0.5) * size.width,
        (1 - (ndcY * 0.5 + 0.5)) * size.height,
      );
    }

    final ordered = [...scene.triangles]
      ..sort((t1, t2) {
        final d1 = (t1.centroid - eye).length2;
        final d2 = (t2.centroid - eye).length2;
        return d2.compareTo(d1); // far → near.
      });

    final paint = Paint()..style = PaintingStyle.fill;
    final gridPaint = Paint()
      ..color = SpaceShiftColors.border.withValues(alpha: 0.6)
      ..strokeWidth = 1;

    _drawGroundGrid(canvas, project, gridPaint);

    for (final tri in ordered) {
      final pa = project(tri.a);
      final pb = project(tri.b);
      final pc = project(tri.c);
      if (pa == null || pb == null || pc == null) continue;

      final shade = (0.35 + 0.65 * tri.normal.dot(_lightDir).clamp(0.0, 1.0))
          .clamp(0.0, 1.0);
      paint.color = Color.lerp(Colors.black, tri.color, shade)!;
      final path = Path()
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy)
        ..lineTo(pc.dx, pc.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawGroundGrid(
    Canvas canvas,
    Offset? Function(vm.Vector3) project,
    Paint paint,
  ) {
    final min = scene.minBounds;
    final max = scene.maxBounds;
    final span = math.max(max.x - min.x, max.z - min.z);
    if (span <= 0) return;
    final step = span / 10;
    for (var i = 0; i <= 10; i++) {
      final x = min.x + step * i;
      final p1 = project(vm.Vector3(x, 0, min.z));
      final p2 = project(vm.Vector3(x, 0, max.z));
      if (p1 != null && p2 != null) canvas.drawLine(p1, p2, paint);

      final z = min.z + step * i;
      final p3 = project(vm.Vector3(min.x, 0, z));
      final p4 = project(vm.Vector3(max.x, 0, z));
      if (p3 != null && p4 != null) canvas.drawLine(p3, p4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Space3DPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.eye != eye ||
        oldDelegate.target != target;
  }
}
