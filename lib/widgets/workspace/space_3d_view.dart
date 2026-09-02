import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../models/space_scene.dart';
import '../../theme/space_shift_colors.dart';

/// scene 크기에 맞춘 near plane 거리 — 카메라가 벽에 아주 가깝게 붙어도
/// (줌인/pan 이후) 그 벽의 정점이 near plane보다 앞에 있다고 착각해
/// 극단적으로 왜곡된 좌표로 투영되지 않도록 한다. [Space3DView]와
/// 테스트가 정확히 같은 값을 쓰도록 공개 함수로 뺐다.
double nearPlaneDistanceFor(double boundingRadius) {
  final radius = boundingRadius <= 0 ? 1000.0 : boundingRadius;
  return math.max(1.0, radius * 0.01);
}

double _farPlaneDistanceFor(double boundingRadius, double eyeToTarget) {
  final radius = boundingRadius <= 0 ? 1000.0 : boundingRadius;
  return radius * 20 + eyeToTarget * 2;
}

/// 현재 카메라(eye/target)로부터 원근 투영 행렬(view * projection)을
/// 만든다 — [Space3DView]의 실제 렌더링과 테스트가 정확히 같은 카메라
/// 수학을 쓰도록 공개 함수로 뺐다(NOMPASS V1 실기 재현 — 벽면 거대
/// 삼각형 artifact의 근본 원인을 재현/검증하는 데 쓰인다).
vm.Matrix4 buildViewProjectionMatrix({
  required vm.Vector3 eye,
  required vm.Vector3 target,
  required double boundingRadius,
  required double aspect,
}) {
  final near = nearPlaneDistanceFor(boundingRadius);
  final far = _farPlaneDistanceFor(boundingRadius, (eye - target).length);
  final proj = vm.makePerspectiveMatrix(45 * math.pi / 180, aspect, near, far);
  final view = vm.makeViewMatrix(eye, target, vm.Vector3(0, 1, 0));
  return proj * view;
}

/// world 좌표 [v]를 [size] 크기의 화면 픽셀 좌표로 투영한다. 카메라
/// 뒤(또는 near plane 바로 앞, clip.w가 0에 아주 가까움)에 있으면 null —
/// 호출부가 이 null을 그냥 무시하면 삼각형의 나머지 두 점만으로 이상한
/// 모양이 그려질 수 있으므로, [Space3DView]는 세 점 중 하나라도
/// null이거나 near plane보다 앞이면 삼각형 자체를 그리지 않는다.
Offset? projectToScreen(vm.Matrix4 viewProj, vm.Vector3 v, Size size) {
  final clip = viewProj.transform(vm.Vector4(v.x, v.y, v.z, 1));
  if (clip.w <= 0.0001) return null;
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  return Offset(
    (ndcX * 0.5 + 0.5) * size.width,
    (1 - (ndcY * 0.5 + 0.5)) * size.height,
  );
}

/// 실기 FAIL 재수정 WO(20번) — "집을 위에서 비스듬히 잘라서 내부가
/// 보이는 인테리어 아이소"를 만들기 위해, 카메라 쪽을 정면으로 향한
/// 외벽(측면만, 상단 테두리는 항상 남긴다)을 숨긴다. 순수 함수로 빼서
/// [Space3DView]와 테스트가 정확히 같은 규칙을 쓰게 한다.
///
/// - 바닥/내벽은 절대 숨기지 않는다([SpaceTriangle.isExteriorWall]이
///   false면 무조건 false).
/// - 벽의 상단(윗면, 법선이 거의 수직)도 숨기지 않는다 — 근접 외벽의
///   테두리 실루엣이 남아 있으면 "벽이 통째로 사라진" 것처럼 보이지
///   않고 실내 구조를 이해하는 데 오히려 도움이 된다.
/// - 나머지(수직에 가까운 외벽 측면)는 그 면의 바깥쪽 법선이 카메라
///   방향을 향하면(수평 성분만 비교 — 위/아래가 아니라 "어느 쪽에서
///   보는지"만 판단) 숨긴다. 매 프레임 카메라 위치로 다시 계산하므로
///   회전하면 숨겨지는 벽도 함께 바뀐다(정적으로 고정하지 않는다).
///
/// [sceneCenter]가 필요한 이유 — 외벽은 두께가 있는 얇은 상자라 4개
/// 측면이 전부 `isExteriorWall=true`로 표시된다(진짜 바깥쪽 피부뿐
/// 아니라, 그 벽의 "안쪽을 향한" 반대쪽 면과 양 끝 마구리 면도 포함).
/// 카메라와 법선만으로 판단하면, 안쪽 벽면인데 우연히 법선이 카메라
/// 쪽을 향하는 경우(특히 반대편에서 바라볼 때 "뒷벽의 실내쪽 면")까지
/// 잘못 숨겨진다 — 뒷벽은 정확히 보여야 할 배경인데 사라지는 버그.
/// 그래서 "법선이 건물 중심에서 바깥으로 향하는 면"인지 먼저 확인한
/// 뒤에야 카메라 방향 검사를 적용한다 — 진짜 바깥쪽 피부만 cutaway
/// 대상이 된다.
bool isCutawayHidden(
  SpaceTriangle tri,
  vm.Vector3 eye, [
  vm.Vector3? sceneCenter,
]) {
  if (!tri.isExteriorWall) return false;
  final normal = tri.normal;
  if (normal.y.abs() > 0.5) return false; // 상단/바닥에 가까운 면은 제외.

  final horizontalNormal = vm.Vector2(normal.x, normal.z);
  if (horizontalNormal.length2 == 0) return false;
  final unitNormal = horizontalNormal.normalized();

  if (sceneCenter != null) {
    final outward = vm.Vector2(
      tri.centroid.x - sceneCenter.x,
      tri.centroid.z - sceneCenter.z,
    );
    if (outward.length2 == 0) return false;
    // 진짜 바깥쪽 피부가 아니면(안쪽 면·마구리 면) cutaway 대상에서
    // 제외한다 — 60도 이내로 바깥 방향과 일치할 때만 "바깥쪽 면"으로
    // 인정.
    if (unitNormal.dot(outward.normalized()) <= 0.5) return false;
  }

  final toCamera = eye - tri.centroid;
  final horizontalToCamera = vm.Vector2(toCamera.x, toCamera.z);
  if (horizontalToCamera.length2 == 0) return false;
  return unitNormal.dot(horizontalToCamera.normalized()) > 0;
}

/// 카메라 pitch(고도각) 허용 범위 — 정확히 수직으로 내려다보면
/// makeViewMatrix의 forward·up이 평행해져 view 행렬이 특이(degenerate)
/// 해지므로, 완전한 90도 대신 약간의 여유를 둔다. [Space3DView]와
/// [ViewPreset.angles]가 정확히 같은 값을 쓰도록 공개 상수로 뺐다.
const double kMinCameraPitch = 0.08;
const double kMaxCameraPitch = math.pi / 2 - 0.08;

/// View Preset — 고정 이미지가 아니라 같은 실제 [SpaceScene]의 카메라
/// 위치(yaw/pitch)만 바꾼다(WO 15번). preset 적용 뒤에도 사용자는 즉시
/// 자유롭게 orbit할 수 있다 — 어떤 값도 잠그지 않는다.
enum ViewPreset { isoDefault, isoLeft, isoRight, isoBack, top }

extension ViewPresetX on ViewPreset {
  String get label => switch (this) {
    ViewPreset.isoDefault => '기본 아이소',
    ViewPreset.isoLeft => '좌측 아이소',
    ViewPreset.isoRight => '우측 아이소',
    ViewPreset.isoBack => '후면 아이소',
    ViewPreset.top => '상면',
  };

  /// (yaw, pitch) — [_Space3DViewState._eye]와 동일한 구면좌표 규약.
  (double, double) get angles {
    final isoPitch = math.atan(1 / math.sqrt2);
    return switch (this) {
      ViewPreset.isoDefault => (math.pi / 4, isoPitch),
      ViewPreset.isoLeft => (-math.pi / 4, isoPitch),
      ViewPreset.isoRight => (3 * math.pi / 4, isoPitch),
      ViewPreset.isoBack => (5 * math.pi / 4, isoPitch),
      ViewPreset.top => (math.pi / 4, kMaxCameraPitch),
    };
  }
}

/// 실제로 조작 가능한 3D 아이소 뷰 — 정적 이미지/pre-render가 아니라
/// [SpaceScene]의 삼각형을 매 프레임 실제로 투영해서 그린다(WO 12번:
/// 회전/확대/축소/pan/화면 맞춤).
///
/// 외부 3D 엔진(flutter_gl/three_dart 등 네이티브 GL 바인딩) 없이,
/// [CustomPainter] 위에서 원근 투영 + 화가 알고리즘(깊이 정렬)으로 직접
/// 그리는 소프트웨어 래스터라이저다 — Windows/Android/Web 어디서도 추가
/// 플랫폼 설정 없이 완전히 동일하게 동작한다(WO 10번 1~3 조건).
class Space3DView extends StatefulWidget {
  const Space3DView({
    super.key,
    required this.scene,
    this.isFullscreenRoute = false,
    this.onExitTo2D,
  });

  final SpaceScene scene;

  /// true면 이미 전체 화면 라우트 안이라 "전체 화면" 버튼을 다시
  /// 보여주지 않는다(WO 13번, 전체 화면 안에서 또 전체 화면 진입 방지).
  final bool isFullscreenRoute;

  /// 실기 FAIL 재수정 WO(2번) — "3D 아이소 → 2D 평면도로 돌아가기"가
  /// 상단 View 탭 전환에만 있어 눈에 띄지 않았다는 실사용 신고 대응.
  /// null이면(전체 화면 라우트 안 등) 버튼을 보여주지 않는다.
  final VoidCallback? onExitTo2D;

  @override
  State<Space3DView> createState() => _Space3DViewState();
}

class _Space3DViewState extends State<Space3DView> {
  late double _yaw;
  late double _pitch;
  late double _distance;
  late vm.Vector3 _target;

  double? _dragScaleStart;
  Offset? _lastFocalPoint;

  /// Desktop/Web — 오른쪽 마우스 버튼을 누른 채 드래그하면 회전 대신
  /// pan으로 처리한다(WO 14번 "우클릭 drag → pan"). [_onPointerDown]이
  /// 그 시작 시점의 버튼 상태를 기록해 둔다 — GestureDetector의
  /// scale/pan 인식기는 버튼 종류를 구분하지 않으므로 Listener로 먼저
  /// 확인한다.
  bool _panningWithMouse = false;

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

  /// View Preset — 카메라 위치(yaw/pitch)만 바꾸고, target/scene은 그대로
  /// 둔다. 적용 뒤에도 계속 자유 orbit 가능하다(값을 잠그지 않음, WO
  /// 15번).
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
        // 두 손가락 — 확대/축소 + pan.
        final start = _dragScaleStart;
        if (start != null && details.scale > 0) {
          _distance = (start / details.scale).clamp(
            widget.scene.boundingRadius * 0.3 + 1,
            widget.scene.boundingRadius * 12 + 5000,
          );
        }
        _panBy(delta);
      } else if (_panningWithMouse) {
        // Desktop/Web 우클릭 드래그 — pan(WO 14번).
        _panBy(delta);
      } else {
        // 한 손가락/마우스 좌클릭 드래그 — 궤도 회전.
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

  Future<void> _enterFullscreen() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: _FullscreenSpace3DPage(scene: widget.scene),
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
          left: 12,
          bottom: 12,
          right: 12,
          child: _ViewPresetBar(onSelected: _applyPreset),
        ),
        Positioned(
          right: 12,
          bottom: 60,
          child: _OrientationCompass(yaw: _yaw),
        ),
        if (widget.onExitTo2D != null)
          Positioned(
            left: 12,
            top: 12,
            child: _IconLabelButton(
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
                _IconLabelButton(
                  icon: Icons.fullscreen_rounded,
                  label: '전체 화면',
                  onTap: _enterFullscreen,
                ),
                const SizedBox(width: 8),
              ],
              _IconLabelButton(
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

/// 3D 아이소 전체 화면 — 좌/우 작업 패널 없이 공간만 최대한 크게
/// 본다(WO 13번). ESC 또는 "닫기" 버튼으로 돌아간다.
class _FullscreenSpace3DPage extends StatelessWidget {
  const _FullscreenSpace3DPage({required this.scene});

  final SpaceScene scene;

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
                child: Space3DView(scene: scene, isFullscreenRoute: true),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: _IconLabelButton(
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

class _IconLabelButton extends StatelessWidget {
  const _IconLabelButton({
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

/// View Preset 선택 바 — 같은 scene의 카메라 위치만 바꾼다(WO 15번).
class _ViewPresetBar extends StatelessWidget {
  const _ViewPresetBar({required this.onSelected});

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

/// 현재 카메라가 어느 방향을 바라보는지 알 수 있는 최소한의 방향
/// 표시(WO 16번) — 장식용 3D 큐브 대신, 실제 [_Space3DViewState._yaw]
/// 값과 그대로 연결된 나침반(위가 항상 "북"이 아니라 지금 바라보는
/// 방향)을 2D로 그린다. 완전한 3D view-cube(각 면 클릭으로 카메라 스냅,
/// 자체 조명/피킹)는 이번 범위에서 만들지 않는다 — 구현 비용 대비
/// 가치가 낮다고 판단해 제외했다(WO 16번 "비용이 과도하면 제외하고
/// 이유를 보고").
class _OrientationCompass extends StatelessWidget {
  const _OrientationCompass({required this.yaw});

  final double yaw;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: CustomPaint(painter: _CompassPainter(yaw: yaw)),
    );
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({required this.yaw});

  final double yaw;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // 카메라가 바라보는 방향(북=화면 위)을 가리키는 바늘 — yaw가
    // 그대로 회전각이라, 사용자가 궤도를 돌리면 이 바늘도 실시간으로
    // 함께 돈다(장식이 아니라 실제 카메라 상태를 반영).
    final angle = -yaw;
    final tip = center + Offset(math.sin(angle), -math.cos(angle)) * radius;
    final tail =
        center +
        Offset(math.sin(angle + math.pi), -math.cos(angle + math.pi)) *
            (radius * 0.5);

    final needlePaint = Paint()
      ..color = SpaceShiftColors.selectionAccent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tail, tip, needlePaint);

    final dotPaint = Paint()..color = SpaceShiftColors.selectionAccent;
    canvas.drawCircle(tip, 3, dotPaint);
    canvas.drawCircle(
      center,
      2,
      Paint()..color = SpaceShiftColors.textSecondary,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) =>
      oldDelegate.yaw != yaw;
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

    final viewProj = buildViewProjectionMatrix(
      eye: eye,
      target: target,
      boundingRadius: scene.boundingRadius,
      aspect: size.width / size.height,
    );

    Offset? project(vm.Vector3 v) => projectToScreen(viewProj, v, size);

    // NOMPASS V1 실기 재현 — Windows 3D 아이소에서 벽면에 거대한 삼각형이
    // 나타나는 사고: near plane에 아주 가깝지만 완전히 뒤는 아닌
    // (0 < clip.w < near 수준) 정점이 project()를 그대로 통과해 극단적으로
    // 먼 화면 좌표로 나비넥타이(모래시계)처럼 왜곡됐다. 삼각형 전체를
    // 화면 밖 극단으로 밀어내는 대신, near plane과 실제로 교차하는
    // 삼각형은 아예 그리지 않는다(안전한 방향 — 한 프레임 누락이
    // 잘못된 거대 삼각형보다 낫다). eye 기준 카메라 forward축 성분
    // (뷰 공간 z가 아니라 world 공간에서 근사)으로 near 미달 정점을
    // 미리 걸러 project() 호출 자체를 줄인다.
    final forward = (target - eye).normalized();
    final near = nearPlaneDistanceFor(scene.boundingRadius);
    bool behindNear(vm.Vector3 v) => (v - eye).dot(forward) <= near;

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
      if (behindNear(tri.a) || behindNear(tri.b) || behindNear(tri.c)) {
        continue;
      }
      // WO 20번 — 카메라를 정면으로 막는 근접 외벽을 숨겨 내부가 보이는
      // "인테리어 아이소"를 만든다(정적 판단이 아니라 매 프레임 현재
      // eye 기준으로 다시 계산 — 회전하면 숨겨지는 벽도 함께 바뀐다).
      if (isCutawayHidden(tri, eye, scene.center)) continue;
      final pa = project(tri.a);
      final pb = project(tri.b);
      final pc = project(tri.c);
      if (pa == null || pb == null || pc == null) continue;
      if (!_isFiniteOffset(pa) ||
          !_isFiniteOffset(pb) ||
          !_isFiniteOffset(pc)) {
        continue;
      }

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

  static bool _isFiniteOffset(Offset o) => o.dx.isFinite && o.dy.isFinite;

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
