# SPACE SHIFT — UI/3D + CAD/DXF integration checkpoint

Date: 2026-10-08 · Machine: PC1 · Branch: `nompass/integration-ui3d-cad`

This branch merges the two SPACE SHIFT lines into one workspace. Original branches,
`main`, and the original working copy (`C:\ASON\SPACE SHIFT\SPACE SHIFT`, branch
`nompass/session-cs-77`, 19 uncommitted files + 1 stash) are unchanged.

## Lines merged

| Line | Commit | Role in the integration |
|---|---|---|
| UI/3D — `nompass/session-cs-75` | 44ee864 | Base: professional workspace shell, 구조 확인/보정, 2D 공간 확정 → 3D, real-time 3D (WO092), AI door/window bridge |
| CAD/DXF — `nompass/port-floorplan-cad-dxf` | 9470d43 | Merged in: mm precision editing, endpoint snap, add wall/door/window, DXF import/export/round-trip, GPT structure analysis with call-cost limits |

Commits on this branch: `c106665` (merge) and `6480a8d` (tool path fixes).

## How the two editors became one

- **Model**: one `CadFloorPlan` and one `CadOpening.copyWith` (it keeps `edited`/`confidence`).
  - `CadElementSource` is the superset `{analyzed, aiSuggested, userEdited, userCreated, userConfirmed}`.
  - The metric helpers (`metricWall(s)`/`metricOpening(s)`/`metricRoom(s)`, `normalizedLengthFromMm`) are shared.
- **Right panel**: the UI/3D panel also carries the CAD controls:
  - wall length (mm) and opening width (mm);
  - add door/window on the selected wall;
  - add wall;
  - GPT 구조 분석 실행;
  - DXF 내보내기.

  While 구조 확인/보정 is on, the add buttons are hidden and the canvas tools (벽 추가 / 문 추가 / 창 추가) are the single add entry. The mm inputs are shown in every mode except 치수 보정.
- **Left rail**: "실측도면 업로드" was "준비중". It now opens the DXF import panel (`CAD 파일 업로드(DXF)`).
- **2D → 3D**: 3D uses only the confirmed 2D snapshot. The confirmation is cleared whenever the draft changes:
  - edit;
  - undo;
  - DXF import;
  - new file;
  - re-analysis;
  - GPT consolidation.

  Before this, 3D could keep showing the previous plan in the DXF import, new file, re-analysis, consolidation and undo cases.
- **3D**: the WO092 real-time 3D stays primary, and the GPT iso image stays an optional "AI 참고 이미지". The pre-WO092 iso-image test from the CAD line is not revived; UI/3D removed it in 4af3070.
- **App identity**: the app stays SPACE SHIFT (`com.example.ason_space`). The SS CAD TEST dev-app branding was not carried over: package id `com.ason.sscadtest`, label, icons, and the orange "개발용" banner.
- **Tests**: CAD-line screen tests open the rail panels first, as the UI/3D tests already do.

## PC1 uncommitted work (backup `C:\ASON\LOCAL PRIVATE\SPACE-SHIFT-PC1-UNCOMMITTED-20261008`)

- 09-03 envelope-first / POC work (13 files) is already committed on the CAD line, byte-identical. Nothing extra was promoted.
- 09-28 path edits (6 tool scripts + `real_image3_source.dart`) are ported in `6480a8d`.
  - `C:\ASON\SPACE_SHIFT\...` paths are now resolved from the repo root.
  - Inputs such as `test/image3.png` are local-only assets and are not in Git.
- `stash@{0}` (cs-70 MASTER #2 label fixes) is superseded by WO071 (8110d6b). It is analyzed only; it was not applied or dropped.

## Verification on PC1 (integration worktree, not the original)

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 36 infos (same count as the UI/3D baseline) |
| `flutter test test` | 796/796 pass; nothing is skipped and no paid AI calls run |
| Test union | All 682 UI/3D + 739 CAD tests are present (union 800). The 4 differences are newer versions of the same test, or one obsolete test (see above) |
| Windows release build | PASS (`ason_space.exe`) |
| Android debug APK | PASS — `com.example.ason_space`, label "SPACE SHIFT" |
| DXF import → screen, round-trip, export | Covered by tests (`dxf_import_flow_test`, `dxf_round_trip_test`, `e2e_dxf_exporter_test`) |
| mm length/width, snap, add wall/opening | Covered by tests (`cad_editing_ops_test`, screen tests) |
| 구조 확인/보정, 2D 확정 → 3D | Covered by tests (UI/3D screen tests) |

**Not verified yet**:
- the real Windows screen;
- install on the Galaxy Tab;
- 3D rotate/zoom/pan by hand;
- a LIVE GPT call;
- opening a real DXF file in a CAD program.

## Open items

1. **Original WorkOrders**: `C:\ASON\LOCAL PRIVATE\SPACE-SHIFT-WO-EXPORT\work_orders.csv` is not there. It needs the user's export from the old NOMPASS Supabase project (`work_orders` table).
2. **NOMPASS #0005 connection**: GitHub App `nompass-runner-664a16` still covers only NEW-NOMPASS + nompass-runner-scratch. After the user adds `Peterchan81/SPACE_SHIFT`:
   - add it to `RUNNER_REPO_ALLOWLIST`;
   - deploy the Control Plane;
   - snapshot #0005;
   - bind #0005 to this branch.
3. Real-screen checks listed under "Not verified yet".
