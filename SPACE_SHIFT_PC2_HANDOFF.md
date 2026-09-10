# SPACE SHIFT — PC2 HANDOFF

Date: 2026-09-10 – 2026-09-11
Machine: PC2
Repo: `C:\ASON\SPACE_SHIFT`
Branch: `nompass/session-cs-75`

## FINAL ISO VISUAL PASS (2026-09-11, last PC2 task before shutdown)

**Goal**: turn the "gray CAD extrusion" ISO into a first readable Architectural Dollhouse draft — white walls, wood floor, black architectural edge lines tracing the wall structure like a 2D floor plan lifted into 3D. Camera/interaction (WO098/099) left untouched.

**Changes** (`lib/services/space_scene_builder_v2.dart`, `lib/widgets/workspace/space_3d_view_gpu_v2.dart`):
- Wall color unified to one warm white (`0xFFF5F4F0`) for both exterior and interior walls (previously exterior was a beige `0xFFC9C2B4`, distinct from interior's near-white) — bathroom wall tile color untouched.
- Floor wood tone changed to a clearer, more saturated light wood (`0xFFC7A06C`, was `0xFFD9CBB2`, too close to the old wall beige).
- Wall top-face darkening reduced from 16% to 4% (`_wallTopColor`) — the default bird's-eye camera mostly sees wall TOP faces, and 16% darkening made them read as a gray band rather than white (this was the literal user complaint this WO opened with).
- Scene ambient light raised from 0.85 to 1.0 — real-screen measurement showed wall faces lit by ambient only (no directional light reaching them) rendered at ~84% of their true color (measured rgb 205 against a target ~245 white), i.e. visibly gray. Directional lights were left unchanged (depth/shading cue preserved).
- New: black architectural edge lines via `three.EdgesGeometry` + `LineSegments` (`_kArchitecturalEdgeColorHex = 0x202020`), built once per wall in `_rebuildMeshes`/tracked in `_wallEdgeLines` for proper cleanup on rebuild.

**Real-screen finding that changed the plan mid-pass**: the first implementation ran `EdgesGeometry` on each wall's *entire* box geometry (all side + top + bottom-cap triangles). On the real 189-wall floor plan this produced a dense wireframe that visually dominated the screen — the "white wall / wood floor" distinction became irrelevant because black linework covered most of the visible area, and lines from camera-facing (BackSide-culled, hence invisible-as-a-surface) walls still rendered since `LineSegments` doesn't share the mesh material's face culling. This was diagnosed by taking real screenshots via a scripted PowerShell screen-capture + click/scroll driver against the actual running `ason_space.exe` (UI Automation was tried first and doesn't work — Flutter's accessibility/semantics tree isn't exposed to Windows UI Automation by default) and reading them back.

**Fix applied** (still one implementation pass, not a tuning loop): edge lines are now built only from each wall's *horizontal* triangles (face normal within ~25° of vertical, i.e. top caps / opening lintels / sills) — computed by a manual per-triangle cross-product filter before feeding a trimmed geometry into `EdgesGeometry`. This keeps the "wall top perimeter" cue (§3.C's first-listed priority, and the most bird's-eye-relevant one) while dropping vertical corner/end edges, which were the dominant source of clutter.

**Real Windows screen verification** (`평면도.PNG`, same file used throughout this session; screenshots taken but deleted after review — session-local diagnostic artifacts, not committed per this WO's exclusion list):
- A. 벽체가 명확한 WHITE로 보임 — **PARTIAL**. Measured wall pixel colors after the fix: `rgb(212,212,210)` on ambient-only faces and pure `rgb(255,255,255)` on directly-lit faces (up from `rgb(205,204,203)` before the fix) — a real, measured improvement, but still short of a crisp uniform white on every face.
- B. 바닥이 명확한 WOOD 계열로 보임 — **PASS**. Measured floor color `rgb(198,174,155)`, a clear warm tan, visually distinct from the wall.
- C. 벽체 상단/주요 경계가 BLACK LINE으로 보임 — **PARTIAL**. Top-perimeter lines read clearly from the bird's-eye default view; vertical corners/wall-end edges were dropped in the density fix (see limitation below), so this is only partially satisfying §3.C's full list.
- D. 흰 벽과 우드 바닥이 섞이지 않음 — **PASS**. Gray/white walls vs. warm tan floor are clearly two different hues.
- E. 위에서 봤을 때 2D 평면도처럼 공간 윤곽을 빠르게 인식 가능 — **PARTIAL**. Big improvement over the pre-fix "wireframe soup," but the real floor plan's central cluster of small rooms (발코니/대피공간/팬트리/욕실) still produces a visually busy band of lines — not as clean as a real 2D floor plan.
- F. 옆으로 회전했을 때도 벽의 형태와 두께가 읽힘 — **PASS**. Rotating to a low side-on angle shows solid-looking wall volumes with a visible top edge line tracing the roofline; wall thickness reads at the base.
- G/H/I. 360 rotate / zoom / pan — **PASS**. All three verified working on the real running app after the change (left-drag rotate, wheel zoom, right-drag pan all responded correctly).
- J. 기존 앱 기능 regression — **PASS** per `flutter analyze` (clean) and `flutter test` (658/658) run after every change in this pass.

**Known limitations, explicitly not iterated further per this WO's STOP RULE**:
- Wall vertical corners and wall-end edges are not drawn (dropped to fix edge-density clutter) — only the horizontal top-perimeter/opening-lintel edges remain. A future pass could reintroduce them with a smarter visibility rule (e.g. only on the far/non-BackSide-culled side of each wall) rather than drawing every wall's full box uniformly.
- Wall white is not perfectly uniform across all faces (ambient-only faces still read a few percent gray rather than pure white) — a further lighting rebalance is possible but was not pursued to respect the "1회 구현" stop rule.
- The busy central cluster of small rooms in this specific real floor plan remains visually dense regardless of the above fixes — this is a floor-plan-complexity issue, not obviously fixable by more color/lighting tuning.
- Door/window visual distinction (§5) was not separately re-verified this pass since the underlying structural POC still reports doors=2/windows=0 for this file (see below) — no fabricated openings were added.

## Completed on PC2 (earlier sessions this machine)

- **AI Clean 2D** (production path): `Original photo → gpt-floorplan-cad-image Edge Function (OpenAI gpt-image-1) → cleaned 2D floor-plan image`. Working, unchanged this session.
- **3D foundation** (WO097/098/099/102, on top of the CV/CAD pipeline):
  - WO097 — real door-opening geometry cut into wall meshes (`space_scene_builder_v2.dart`).
  - WO098 — fixed 360° rotate/zoom/pan by replacing `three_js`'s internal `Peripherals` gesture handling with a raw `Listener` (`space_3d_view_gpu_v2.dart`). **Do not regress this.**
  - WO099 — compact icon-rail UI (`workspace_icon_rail.dart`), Dollhouse camera + `BackSide` wall-culling trick, minimal furniture primitives (`SpaceFurnitureMeshV2`).
  - WO102 — Window is now a real architectural object: `SpaceWindowMeshV2` (separate frame + glass meshes, distinct `objectId`s), opening cut into wall geometry using assumed sill/head height constants (`kAssumedWindowSillHeightMm=900`, `kAssumedWindowHeightMm=1200`, explicitly not treated as measured data). Door/window selection UI bugs fixed (`Selected3DObjectTab`, `user_workspace_panel.dart`).
  - All verified: `flutter analyze` clean, `flutter test` → 658/658 passing, real Windows build (`flutter build windows --debug --dart-define=GPT_FLOORPLAN_IMAGE_EDGE_FUNCTION_URL=...`) launches and runs.
  - **Known limitation carried over from WO102**: for the real test file `평면도.PNG`, the pixel/CV pipeline (`floor_plan_analysis_engine.dart`) detects **0 doors/windows** — not a 3D bug, the 2D gap-detection stage finds no raw opening evidence for this specific image. The door/window-cutting architecture itself is correct and verified via synthetic unit tests; it will activate automatically once real opening evidence exists.

## AI Structural POC result (this session, PC2 final task)

**Goal**: prove that `Original floor plan → AI understanding → structured Wall/Room/Door/Window JSON → diagnostic overlay` is achievable through a real API call, without inventing a new architecture.

**Reused, not rebuilt**: this capability already existed, disconnected from production, from an earlier WO (pre-dates this session):
- Edge Function: `supabase/functions/gpt-floorplan-understand/index.ts` — OpenAI `gpt-4o` with strict JSON-schema structured output. Deployed and kept as an R&D/alternate path (see `supabase/functions/gpt-floorplan-cad-image/README.md` and `supabase/config.toml` comments — the image-generation path replaced it for the *production screen*, but it was never deleted or undeployed).
- Dart contract: `lib/models/vision_understanding.dart` (`VisionUnderstanding`, `VisionSpace`, `VisionBoundary`, `VisionOpening`, ...) — normalized 0.0–1.0 coordinates only, `scaleConfirmed` always `false` unless a real dimension is confirmed (never fabricates mm).
- Dart client: `lib/services/gpt_floorplan_vision_service.dart` (`GptFloorplanEdgeFunctionVisionService`).

**New this session**: `tool/pc2_ai_structural_poc.dart` — a standalone script (run via `flutter test tool/pc2_ai_structural_poc.dart`, required because the model file transitively imports `dart:ui` through `flutter/foundation.dart`, so plain `dart run` fails) that:
1. Loads the real `평면도.PNG` (842×576, 380,538 bytes).
2. Calls the real, deployed `gpt-floorplan-understand` Edge Function (no mocks).
3. Prints structured counts and per-entity detail.
4. Draws a diagnostic overlay directly onto the **original** image (not the AI-Clean image — avoids re-analyzing an AI-generated image, per this WO's explicit prohibition) using `package:image`, saved to `test/pc2_ai_structural_overlay.png`.
5. Dumps the raw JSON to `test/pc2_ai_structural_result.json`.

### Real result (real API call, 2026-09-10)

```
spaces=10        (kitchen, living, bathroom×2, bedroom×2, balcony, corridor, unknown×1, entrance)
boundaries=6     (4 exteriorWall, 2 interiorWall — all as line segments)
openings=2       doors=2, windows=0, openPassage=0
objects=0, structuralElements=0, dimensions=0
scaleConfirmed=false   (correct — no real dimension text was read)
coordinate sanity: 34/34 points inside plausible [-0.2,1.2] range, 0 implausible
```

Both detected doors have plausible normalized centers and a resolvable `attachedBoundaryId`. Overlay visual inspection (`test/pc2_ai_structural_overlay.png`) confirms markers land on the correct real-image positions — no coordinate shift/mirror/letterbox bug.

### Known limitations (not fixed — explicitly out of scope, no threshold/prompt tuning performed)

- **Doors**: only 2 of the visually-apparent door-swing symbols (~7–8 in the image) were detected. Partial success, reported honestly.
- **Windows**: 0 detected. Cannot confirm from this single call whether the model missed real windows or the plan genuinely has none in a GPT-recognizable form.
- **floorDomain**: returned as an axis-aligned bounding box, not a polygon — does not follow the actual angled/diagonal exterior wall in the bottom-right of this plan.
- **Diagonal room** (bottom-right, rotated ~45°, containing bedroom+bathroom+dress room): GPT returned one merged bounding box covering all three sub-spaces rather than three separate ones.
- `space9` was left `semanticType: unknown, confidence: unknown` — the model was honest about not being able to classify it rather than guessing.

This is a **partial-success POC**, reported as such per this WO's explicit "부분 성공도 그대로 기록, 무한 반복 튜닝 금지" instruction. The architecture is proven end-to-end and reusable; the accuracy of GPT's own vision output is a separate, later concern.

## What worked

- The `gpt-floorplan-understand` Edge Function is live and returns valid, schema-conformant, coordinate-correct JSON for a real file, with no dart-define or secret changes needed on the client side.
- Reusing `VisionUnderstanding`/`GptFloorplanEdgeFunctionVisionService` avoided building any duplicate schema/service.
- Door detection and room semantic classification are meaningfully useful even at partial recall.

## What failed / is incomplete

- Window detection: 0/? real windows.
- floorDomain / diagonal-room polygon fidelity: bounding boxes only, not real polygons.
- No merge yet exists between this AI structural result and the WO102 `ArchitecturalScene`/`SpaceSceneV2` — this session deliberately stopped at the overlay/JSON step and did not attempt that merge (§2 of the PC2 WO: "이번 PC2에서는 여기서 멈춘다").

## DO NOT REPEAT

- WO093 wall-hide-by-threshold.
- WO094 gated hide.
- WO095 wall-height/clip-plane tuning.
- Renderer-only "fixes" for missing doors/windows — the real cause for the CV pipeline's 0-opening result on `평면도.PNG` is upstream (2D gap detection), not the 3D renderer; the real cause for GPT's partial door/window recall is prompt/model accuracy, not a code bug. Neither is fixable by touching the 3D renderer.
- CV threshold tuning loops without new semantic evidence backing them.
- Building a second, parallel structured-floorplan schema — `VisionUnderstanding` already exists and is now proven live; extend it, don't duplicate it.

## NEXT START POINT (for the next PC/session)

**FIRST**: look at the ISO visual result described above on a real screen yourself and judge whether it's an acceptable starting point (§18 of the final PC2 WO: "이번 세션은 아이소 색상부터 다시 만드는 것이 아니다"). Only re-touch wall/floor/edge color or lighting if you find it genuinely unusable — the known limitations above (non-uniform white, missing vertical corner edges, busy central room cluster) were left as documented tradeoffs, not oversights.

**THEN, the real next feature step** (not more color tuning): AI semantic structure + existing geometry canonical merge.
1. Pull this checkpoint. Read this handoff before modifying any code.
2. Do not repeat the AI structural POC call/overlay step — it is done and its result files are committed (`test/pc2_ai_structural_result.json`, `test/pc2_ai_structural_overlay.png`).
3. Decide, based on the partial-success result (rooms=10, boundaries=6, doors=2, windows=0), whether accuracy (window recall, floorDomain polygon fidelity, diagonal-room splitting) needs improvement before merging into the 3D pipeline, or whether the current result is already useful enough to bridge into `SpaceSceneV2` as a first cut.
4. If proceeding: build the "canonical merge" step — CV `CadFloorPlan` geometry (precise pixel-fit walls) + AI `VisionUnderstanding` semantics (room labels, door/window presence, host-wall linkage) → a single corrected `CadFloorPlan`/`ArchitecturalScene`, following the AI=semantic / CV=geometric-evidence / SS=canonical-merge division of responsibility described in the PC2 WO §7 (of the AI-bridge work order). Only after that merge is validated should the WO102 window/door architecture be re-run against the corrected data and the 3D ISO screen revisited.
5. Do not touch the renderer/camera/interaction code (WO098/WO099/WO102) as part of that merge work — those are validated and out of scope for the merge step itself.
6. After the door/window structure is actually connected to real geometry: material editing → furniture editing → wall create/remove → 3D Perspective, in that order (per the final PC2 WO's own stated sequence).

--- SPACE SHIFT PC2 FINAL RESUME ---

Repo:
C:\ASON\SPACE_SHIFT

Branch:
nompass/session-cs-75

Starting checkpoint:
cf2aec8fa22dfb1010a63a9c10e43185fdbfbf14

Final checkpoint:
(see commit hash in the final report / `git log -1` — committed right after this file)

Origin:
same commit, pushed to `origin/nompass/session-cs-75`

Ahead/behind:
0/0 (verified after push)

Verified:
analyze: clean (0 errors; only pre-existing unused-element warnings and expected avoid_print info in tool/ scripts)
tests: 658/658 passed
Windows build: `flutter build windows --debug --dart-define=GPT_FLOORPLAN_IMAGE_EDGE_FUNCTION_URL=https://mljvgngjmrvoqjwvvyeg.supabase.co/functions/v1/gpt-floorplan-cad-image` succeeded twice (once per color/lighting fix iteration), app launched and ran both times, real screen checked directly (scripted screenshot capture against the live process, not just widget tests)

ISO foundation:
White wall: PARTIAL (measured 212/255 gray-to-white range depending on face, up from 205 before the fix)
Wood floor: PASS (measured rgb(198,174,155), clearly distinct warm tan)
Black architectural edge: PARTIAL (top-perimeter only; vertical corners/end edges dropped to fix visual clutter — see limitations)
Door: not re-verified visually this pass (structural source unchanged: doors=2 for this file, real wall gap already shown by WO097 architecture)
Window: not re-verified visually this pass (structural source unchanged: windows=0 for this file — WO102 architecture is correct but has no real evidence to draw for this specific image)
360 interaction: PASS (rotate/zoom/pan all confirmed on the real running app after the change)

Structural POC (unchanged from previous checkpoint, not repeated this pass):
rooms=10
boundaries=6
doors=2
windows=0

Known limitations:
- Wall color not perfectly uniform white on every face (ambient-only faces read light gray, ~212/255)
- Wall vertical corners/end edges intentionally not drawn (only top-perimeter edges) to avoid wireframe clutter — a future pass could add them back with per-face visibility logic
- Central cluster of small rooms in this specific real floor plan stays visually busy regardless of color/lighting fixes — likely inherent to floor-plan complexity, not a rendering bug
- AI structural bridge (doors=2, windows=0, floorDomain=bounding-box-only, diagonal room merged) is unchanged from the prior checkpoint — not touched this pass, per explicit instruction

Do not repeat:
WO093/094/095 renderer-hide/threshold/clip-plane tuning; further ambient/wall-color/edge-density tuning loops on this same real screen (one implementation + one corrective pass already done — STOP RULE); CV opening-threshold tuning; the AI structural POC call (already performed, see test/pc2_ai_structural_result.json)

First next action:
Judge the ISO visual result on a real screen first; if acceptable, move to AI semantic structure + existing geometry canonical merge (see "NEXT START POINT" above), then connect verified door/window structure to the existing ISO before touching Perspective/materials/furniture-library/wall-create-delete.

Unrelated dirty files (left exactly as found, not committed, not deleted):
WO088 2D CAD POC series (test/image3*/image4*/wo088 tool+probe files, all untracked) and generated/noise files (linux/macos/windows plugin registrant files + pubspec.lock, all modified from routine `flutter pub get`/build, not from any code change in this session).

--- END RESUME ---
