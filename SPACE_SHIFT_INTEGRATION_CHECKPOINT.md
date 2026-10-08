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

## PC2 HANDOFF (PC1 final save, 2026-10-08)

PC1 stops development here. PC2 continues from GitHub.

### Where to start

| Item | Value |
|---|---|
| Repository | https://github.com/Peterchan81/SPACE_SHIFT |
| Start branch | `nompass/integration-ui3d-cad` (HEAD = this checkpoint commit or newer) |
| Merged sources (unchanged) | `nompass/session-cs-75` 44ee864 (UI/3D), `nompass/port-floorplan-cad-dxf` 9470d43 (CAD/DXF) |
| GitHub `main` (old, unchanged) | bb48bc9 — do not use it as a base |
| PC1 Flutter | 3.44.4 stable |
| NOMPASS | `Peterchan81/NEW-NOMPASS` main 7f5b846, Control Plane dd5bc957 (runs on Cloudflare, independent of PC1) |

### Recoverable on PC2 (from GitHub)

- All integrated code and tests (796/796 on PC1), plus this checkpoint.
- The 09-03 POC/envelope-first work: already part of the branch.
- The 09-28 tool path fixes: commit 6480a8d.

### PC1-only (not in GitHub, and PC2 must not assume it can reach it)

- Original working copy `C:\ASON\SPACE SHIFT\SPACE SHIFT` (branch `nompass/session-cs-77` = 44ee864).
  - 19 uncommitted files and `stash@{0}` (cs-70 MASTER #2 label fixes) are kept on purpose.
  - Everything in them is already in this branch or superseded (see above), so PC2 does not need them.
- Private backup `C:\ASON\LOCAL PRIVATE\SPACE-SHIFT-PC1-UNCOMMITTED-20261008`: patch, stash export, sha256 manifests.
- Local test assets that are not in Git, such as `test/image3.png` for the POC tools, and the real floor-plan images used in earlier LIVE checks.
- Local worktrees `SPACE_SHIFT_MERGE` (`nompass/integration-ui3d-cad-wip`, same content as 6480a8d) and `SPACE_SHIFT_BASELINE_CAD`.
- Build outputs (Windows exe, debug APK) and the test/build logs.

Do not upload secrets, tokens, the private backup, or a Supabase WorkOrder CSV to this public repository. If PC2 needs any of them, the user moves them through a private channel they approve.

### BLOCKED (user action needed)

1. **WorkOrder originals**: the user exports `work_orders` from the old NOMPASS Supabase project (mljvgngjmrvoqjwvvyeg) as CSV and saves it outside the repo.
2. **GitHub App access**: the user adds `Peterchan81/SPACE_SHIFT` to installation 167195182 (`nompass-runner-664a16`). On 2026-10-08 `/runner/github-check` still lists only NEW-NOMPASS + nompass-runner-scratch.
3. **NOMPASS #0005 repo binding**: this depends on 2. #0005 and #0005-02 are unchanged and unbound (`/project-repos` binds only #0006).

### Not verified yet (no user permission needed)

- Windows real-screen check of the integrated workspace.
- Galaxy Tab install and manual operation.
- 3D rotate/zoom/pan by hand.
- A real DXF file opened in a CAD program.
- A LIVE GPT call, which needs dart-defines or a key kept outside Git.

### PC2 order of work

1. RESET CONTINUE → check that the branch HEAD matches origin.
2. Check the PC2 dev environment (Flutter, Android SDK) → `flutter pub get`, `flutter analyze`, `flutter test test`.
3. Windows real screen: upload → 구조 확인/보정 → mm edits → 2D 공간 확정 → 3D; 실측도면 업로드 → DXF import/export.
4. If possible: install on the Galaxy Tab and operate.
5. Real DXF file round-trip in a CAD program.
6. LIVE GPT check (the user provides the key/URL locally; never commit it).
7. **[user]** Supabase WorkOrder CSV recovery.
8. **[user]** GitHub App access for SPACE_SHIFT → confirm with `/runner/github-check`.
9. Add SPACE_SHIFT to `RUNNER_REPO_ALLOWLIST` (`cloud/control-plane/wrangler.jsonc`) → deploy.
10. Snapshot #0005 → bind it to `nompass/integration-ui3d-cad` (not main).
11. Resume SPACE SHIFT development from NOMPASS #0005.

Steps 1–6 do not depend on 7–8 and can go ahead while those wait.
