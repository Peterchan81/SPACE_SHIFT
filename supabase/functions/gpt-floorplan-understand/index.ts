// SPACE SHIFT - GPT 평면도 구조 이해 요청을 받는 Supabase Edge Function.
//
// GPT FLOORPLAN → STRUCTURED 2D → REAL 3D ISO FLOW WO — Flutter 앱은
// OpenAI를 절대 직접 호출하지 않는다(§5). 반드시 이 Edge Function을
// 거쳐서만 GPT 평면도 분석을 요청한다. OpenAI Secret은 Supabase Secret
// OPENAI_API_KEY에서만 읽으며 클라이언트로 전달하거나 응답/로그에
// 기록하지 않는다 — generate-interior/index.ts와 정확히 같은 보안
// 패턴(CORS/JSON 검증/제네릭 에러 메시지/secret 미노출)을 그대로 따른다.
//
// GPT의 역할은 "이 평면도가 무엇인지 이해"까지다(§4) — 정밀 좌표 확정은
// Flutter 쪽 HintedGeometryExtractor/TopologyValidator가 픽셀 evidence로
// 다시 검증한다. 그래서 이 함수는 GPT에게 "정밀 CAD 좌표"가 아니라 "대략
// 어디"(bounding box/segment/point hint)만 요청하고, 그 결과를
// VisionUnderstanding 계약(ason_space/lib/models/vision_understanding.dart
// 의 toJson()/fromJson()과 정확히 같은 모양)으로 포장해 돌려준다 — GPT가
// 직접 그 깊은 중첩 스키마를 채우게 하는 대신, GPT에게는 훨씬 단순한
// 중간 스키마(IntermediateResult)만 구조화 출력으로 요청하고, 이 함수가
// 결정론적으로 최종 계약 모양으로 변환한다(모델이 깊은 중첩 스키마를
// 정확히 못 지키는 리스크를 줄인다).
//
// 실제 mm 치수는 GPT가 임의로 만들지 않는다(§3) — scaleConfirmed는 이
// 함수가 항상 false로 고정하고, GPT에게도 그런 값을 요청하지 않는다.

const OPENAI_ENDPOINT = "https://api.openai.com/v1/chat/completions";
const OPENAI_MODEL = "gpt-4o";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface UnderstandRequestBody {
  image?: unknown;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// GPT에게 요청하는 단순화된 중간 스키마 — 전부 이미지 전체 기준
// 0.0~1.0 정규화 좌표다. VisionUnderstanding의 깊은 중첩(geometryHint
// kind 분기 등)을 GPT에게 직접 맡기지 않고, 이 함수가 결정론적으로
// 변환한다.
const RESPONSE_JSON_SCHEMA = {
  name: "floorplan_understanding",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["floorDomainPolygon", "spaces", "boundaries", "openings", "notes"],
    properties: {
      floorDomainPolygon: {
        type: "array",
        description:
          "건물 외곽(exterior envelope) polygon 꼭짓점을 시계 또는 반시계 순서로, 정규화 좌표(0.0~1.0)로 나열한다. 최소 3점.",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["x", "y"],
          properties: { x: { type: "number" }, y: { type: "number" } },
        },
      },
      spaces: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "label", "semanticType", "confidence", "boundingBox"],
          properties: {
            id: { type: "string" },
            label: {
              type: ["string", "null"],
              description: "도면에 실제로 쓰인 이름이 보이면 그 텍스트, 없으면 null(지어내지 않는다).",
            },
            semanticType: {
              type: "string",
              enum: [
                "bedroomMaster", "bedroom", "living", "kitchen", "bathroom",
                "entrance", "utility", "pantry", "balcony", "mechanicalRoom",
                "corridor", "unknown",
              ],
            },
            confidence: { type: "string", enum: ["high", "medium", "low", "unknown"] },
            boundingBox: {
              type: "object",
              additionalProperties: false,
              required: ["minX", "minY", "maxX", "maxY"],
              properties: {
                minX: { type: "number" }, minY: { type: "number" },
                maxX: { type: "number" }, maxY: { type: "number" },
              },
            },
          },
        },
      },
      boundaries: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "boundaryType", "confidence", "start", "end"],
          properties: {
            id: { type: "string" },
            boundaryType: { type: "string", enum: ["exteriorWall", "interiorWall", "virtualBoundary", "unknown"] },
            confidence: { type: "string", enum: ["high", "medium", "low", "unknown"] },
            start: {
              type: "object", additionalProperties: false, required: ["x", "y"],
              properties: { x: { type: "number" }, y: { type: "number" } },
            },
            end: {
              type: "object", additionalProperties: false, required: ["x", "y"],
              properties: { x: { type: "number" }, y: { type: "number" } },
            },
          },
        },
      },
      openings: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "openingType", "confidence", "center", "attachedBoundaryId"],
          properties: {
            id: { type: "string" },
            openingType: { type: "string", enum: ["door", "window", "openPassage"] },
            confidence: { type: "string", enum: ["high", "medium", "low", "unknown"] },
            center: {
              type: "object", additionalProperties: false, required: ["x", "y"],
              properties: { x: { type: "number" }, y: { type: "number" } },
            },
            attachedBoundaryId: { type: "string" },
          },
        },
      },
      notes: {
        type: "array",
        items: { type: "string" },
        description: "치수 텍스트가 안 보이는 등, 사용자가 알아야 할 불확실성/제약 사항.",
      },
    },
  },
} as const;

const SYSTEM_PROMPT =
  "You are an architectural floor plan understanding assistant for an interior " +
  "design app. You are given one floor plan image. Identify the building's " +
  "exterior envelope, distinct usable rooms/spaces (with a best-guess semantic " +
  "type such as bedroom/bathroom/kitchen/living/etc.), wall segments (exterior " +
  "vs interior), and door/window openings. All coordinates MUST be normalized " +
  "to the full image (0.0 at left/top, 1.0 at right/bottom) — never pixel or mm " +
  "values. Be honest about uncertainty: use confidence \"low\" or \"unknown\" " +
  "rather than guessing precisely. Do NOT invent a room label that is not " +
  "actually printed on the drawing — use null instead. Do NOT infer or state " +
  "any real-world millimeter dimension — you have no way to know the true " +
  "scale from a raster image alone; leave that to a later calibration step. " +
  "If a wall or opening is ambiguous, still report it with lower confidence " +
  "rather than omitting it, unless you are not confident it exists at all. " +
  "Every opening's attachedBoundaryId MUST exactly match the id of one of the " +
  "boundaries you reported — never invent an id that isn't in your own " +
  "boundaries list.";

function jsonError(message: string, status: number): Response {
  return jsonResponse({ success: false, message }, status);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonError("POST 요청만 허용됩니다.", 405);
  }

  let body: UnderstandRequestBody;
  try {
    body = await req.json();
  } catch (_error) {
    return jsonError("요청 본문이 올바른 JSON이 아닙니다.", 400);
  }

  const { image } = body;
  if (typeof image !== "string" || image.trim().length === 0) {
    return jsonError("image 값이 필요합니다.", 400);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return jsonError("GPT 평면도 분석 기능이 아직 설정되지 않았습니다.", 503);
  }

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 55_000);
    let openaiResponse: Response;
    try {
      openaiResponse = await fetch(OPENAI_ENDPOINT, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: OPENAI_MODEL,
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            {
              role: "user",
              content: [
                { type: "text", text: "Analyze this floor plan image." },
                { type: "image_url", image_url: { url: image } },
              ],
            },
          ],
          response_format: { type: "json_schema", json_schema: RESPONSE_JSON_SCHEMA },
          max_tokens: 4096,
        }),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }

    if (!openaiResponse.ok) {
      console.error("OpenAI 요청 실패 상태:", openaiResponse.status);
      return jsonError("GPT 평면도 분석 요청에 실패했습니다.", 502);
    }

    const openaiPayload = await openaiResponse.json().catch(() => null);
    const rawContent = openaiPayload?.choices?.[0]?.message?.content;
    if (typeof rawContent !== "string") {
      return jsonError("GPT 평면도 분석 결과가 비어 있습니다.", 502);
    }

    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(rawContent);
    } catch (_error) {
      return jsonError("GPT 평면도 분석 결과 형식이 올바르지 않습니다.", 502);
    }

    const understanding = toVisionUnderstanding(parsed);
    return jsonResponse({ success: true, understanding });
  } catch (error) {
    console.error(
      "gpt-floorplan-understand 처리 실패:",
      error instanceof Error ? error.name : "unknown",
    );
    return jsonError("평면도 분석 중 오류가 발생했습니다.", 500);
  }
});

/**
 * GPT의 단순화된 중간 스키마를, Flutter
 * `VisionUnderstanding.fromJson`이 그대로 읽을 수 있는 최종 계약 모양으로
 * 결정론적으로 변환한다 — GPT는 이 깊은 중첩 구조를 직접 채우지 않는다.
 */
// deno-lint-ignore no-explicit-any
function toVisionUnderstanding(parsed: any): Record<string, unknown> {
  const floorDomainPoints = Array.isArray(parsed?.floorDomainPolygon)
    ? parsed.floorDomainPolygon
    : [];

  return {
    floorDomain: {
      id: "floor-domain",
      type: "floorDomain",
      confidence: floorDomainPoints.length >= 3 ? "medium" : "unknown",
      source: "vision",
      geometryHint: floorDomainPoints.length >= 3
        ? { kind: "polygon", points: floorDomainPoints.map(toPointJson) }
        : null,
      notes: [],
    },
    spaces: (Array.isArray(parsed?.spaces) ? parsed.spaces : []).map((s: any) => ({
      id: s.id,
      type: "space",
      confidence: s.confidence ?? "unknown",
      source: "vision",
      geometryHint: {
        kind: "boundingBox",
        minX: s.boundingBox?.minX,
        minY: s.boundingBox?.minY,
        maxX: s.boundingBox?.maxX,
        maxY: s.boundingBox?.maxY,
      },
      notes: [],
      label: s.label ?? null,
      semanticType: s.semanticType ?? "unknown",
      adjacentSpaceIds: [],
      containedObjectIds: [],
    })),
    boundaries: (Array.isArray(parsed?.boundaries) ? parsed.boundaries : []).map((b: any) => ({
      id: b.id,
      type: "boundary",
      confidence: b.confidence ?? "unknown",
      source: "vision",
      geometryHint: { kind: "segment", start: toPointJson(b.start), end: toPointJson(b.end) },
      notes: [],
      boundaryType: b.boundaryType ?? "unknown",
      adjacentSpaceIds: [],
    })),
    openings: (Array.isArray(parsed?.openings) ? parsed.openings : []).map((o: any) => ({
      id: o.id,
      type: "opening",
      confidence: o.confidence ?? "unknown",
      source: "vision",
      geometryHint: { kind: "point", point: toPointJson(o.center) },
      notes: [],
      openingType: o.openingType ?? "door",
      // attachedBoundaryId는 boundaries[].id 중 하나를 정확히 가리켜야
      // 한다(SYSTEM_PROMPT/스키마가 GPT에게 그렇게 요청한다) — 여기서는
      // 그 값을 그대로 옮기기만 한다.
      attachedBoundaryId: typeof o.attachedBoundaryId === "string" ? o.attachedBoundaryId : null,
      connectsSpaceIds: [],
    })),
    objects: [],
    structuralElements: [],
    dimensions: [],
    // §3 — 실제 치수 근거(인쇄된 치수 텍스트 등)를 이 파이프라인이 아직
    // 파싱하지 않으므로 항상 false로 고정한다. GPT가 문 폭 등으로 mm를
    // 임의 추정해도 이 값을 true로 만들지 않는다.
    scaleConfirmed: false,
    notes: Array.isArray(parsed?.notes) ? parsed.notes : [],
  };
}

// deno-lint-ignore no-explicit-any
function toPointJson(p: any): { x: number; y: number } {
  return { x: Number(p?.x ?? 0), y: Number(p?.y ?? 0) };
}
