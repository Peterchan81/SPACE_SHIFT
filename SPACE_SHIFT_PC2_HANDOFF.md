# SPACE SHIFT — PC2 HANDOFF

Date: 2026-09-10
Machine: PC2
Repo: `C:\ASON\SPACE_SHIFT`
Branch: `nompass/session-cs-75`

## Completed on PC2

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

1. Pull this checkpoint. Read this handoff before modifying any code.
2. Do not repeat the AI structural POC call/overlay step — it is done and its result files are committed (`test/pc2_ai_structural_result.json`, `test/pc2_ai_structural_overlay.png`).
3. Decide, based on the partial-success result above, whether accuracy (window recall, floorDomain polygon fidelity, diagonal-room splitting) needs improvement before merging into the 3D pipeline, or whether the current 2-door/10-space result is already useful enough to bridge into `SpaceSceneV2` as a first cut.
4. If proceeding: build the "canonical merge" step — CV `CadFloorPlan` geometry (precise pixel-fit walls) + AI `VisionUnderstanding` semantics (room labels, door/window presence, host-wall linkage) → a single corrected `CadFloorPlan`/`ArchitecturalScene`, following the AI=semantic / CV=geometric-evidence / SS=canonical-merge division of responsibility described in the PC2 WO §7. Only after that merge is validated should the WO102 window/door architecture be re-run against the corrected data and the 3D ISO screen revisited.
5. Do not touch the renderer/camera/interaction code (WO098/WO099/WO102) as part of that merge work — those are validated and out of scope for the merge step itself.

--- SPACE SHIFT RESUME ---

Repo:
C:\ASON\SPACE_SHIFT

Branch:
nompass/session-cs-75

Checkpoint:
(see commit hash in the final report / `git log -1`)

Origin:
same commit, pushed to `origin/nompass/session-cs-75`

Verified:
flutter analyze: clean (0 errors; only pre-existing unused-element warnings and expected avoid_print info in tool/ scripts)
flutter test: 658/658 passed
flutter build windows --debug --dart-define=GPT_FLOORPLAN_IMAGE_EDGE_FUNCTION_URL=https://mljvgngjmrvoqjwvvyeg.supabase.co/functions/v1/gpt-floorplan-cad-image: succeeded, app launched and ran

Structural POC:
Real gpt-floorplan-understand call on 평면도.PNG → spaces=10, boundaries=6, doors=2, windows=0, scaleConfirmed=false, 0/34 implausible coordinates. Partial success, recorded honestly, not tuned further.

Do not repeat:
WO093/094/095 renderer-hide/threshold/clip-plane tuning; re-running the AI structural POC call (already done, see test/pc2_ai_structural_result.json); building a second structured-floorplan schema (VisionUnderstanding already exists and works).

First action after pull:
Read this file, then read test/pc2_ai_structural_result.json + test/pc2_ai_structural_overlay.png, then decide on the CV+AI canonical-merge step described in "NEXT START POINT" above.

Protected/unrelated work:
WO088 2D CAD POC series (test/image3*/image4*/wo088 tool+probe files) remains uncommitted/untouched on this machine's worktree — not part of this checkpoint, not evaluated, not modified. NOMPASS V1/V2, SS CAD TEST (test/vision_cad_poc/pixel_wall_v4/metric_cad_test.dart and related), and Group-B protected files were not modified.

--- END RESUME ---
