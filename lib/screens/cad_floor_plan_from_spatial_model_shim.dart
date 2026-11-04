/// SS011 — [CadEditorScreen]이 SS010 레거시 cadData 페이로드({'model': SSSpatialModel
/// JSON})를 읽을 때 쓰는 아주 작은 이름 재노출 shim. 기존 [buildCadFloorPlanFromSpatialModel]
/// (lib/models/cad_floor_plan.dart, Canonical 변환 — 화면/DXF/3D가 모두 공유하는 바로 그 함수)을
/// 새 이름으로 감싸지 않고 그대로 다시 내보내기만 한다 — 변환 로직을 복제하지 않는다.
library;

import '../models/cad_floor_plan.dart';
import '../models/ss_spatial_model.dart';

CadFloorPlan cadFloorPlanFromSpatialModelCompat(SSSpatialModel model) => buildCadFloorPlanFromSpatialModel(model);
