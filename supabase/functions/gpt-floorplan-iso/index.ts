// SPACE SHIFT - GPT 3D 아이소메트릭 이미지 생성 Edge Function.
//
// V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO — GPT가 만든 Clean CAD
// 스타일 2D 평면도(gpt-floorplan-cad-image의 결과)를 입력으로 받아,
// 같은 공간 배치를 반영한 3D 아이소메트릭 인테리어 이미지를 새로
// 그려서 돌려준다. 기존 실시간 geometry 3D(SpaceSceneBuilderV2/
// three.js)는 이 함수와 무관하게 그대로 보존된다 — 이 함수는 "AI가
// 그려주는 아이소 이미지"라는, V1 1차 완성을 위한 별도의 표현 경로다.
//
// Flutter 앱은 OpenAI를 절대 직접 호출하지 않는다 — 이 Edge Function만
// 거친다. OpenAI Secret은 Supabase Secret OPENAI_API_KEY에서만 읽으며
// (gpt-floorplan-cad-image와 동일한 secret을 공유한다) 클라이언트로
// 전달하거나 응답/로그에 기록하지 않는다.

const OPENAI_IMAGE_EDIT_ENDPOINT = "https://api.openai.com/v1/images/edits";
const OPENAI_IMAGE_MODEL = "gpt-image-1";

// V1 WO §7 — 정확한 기본 재질/시점 계약을 그대로 반영한다.
const ISO_STYLE_PROMPT =
  "Using the attached clean CAD-style 2D floor plan as the exact spatial " +
  "reference, generate a 3D isometric interior architectural " +
  "visualization of this same space, viewed from an elevated bird's-eye " +
  "isometric angle (like a dollhouse/cutaway view looking down and in). " +
  "The room layout, wall positions, and door/window openings must match " +
  "this floor plan as closely as possible — do not add rooms that are " +
  "not in the floor plan, do not remove or resize rooms, and do not " +
  "change the overall shape of the building. " +
  "Default materials (apply these unless a room is clearly a bathroom): " +
  "interior walls are plain white; normal room floors are wood flooring. " +
  "For any room that is clearly a bathroom (based on the floor plan " +
  "shape/labels), use tile for both the floor and the walls of that " +
  "room instead. " +
  "Reflect the door and window positions from the floor plan as real " +
  "openings in the 3D walls. " +
  "Furniture must be minimal and basic only (e.g. a bed in a bedroom, a " +
  "sofa in a living room) just enough to convey each room's function — " +
  "do not add elaborate interior design, decor, or styling beyond that. " +
  "Keep lighting simple and neutral. This is a clean architectural " +
  "massing/interior study image, not a decorated interior design " +
  "render.";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface IsoRequestBody {
  image?: unknown;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status: number): Response {
  return jsonResponse({ success: false, message }, status);
}

/** "data:image/png;base64,AAAA..." → {bytes, mimeType}. */
function decodeDataUri(dataUri: string): { bytes: Uint8Array; mimeType: string } | null {
  const match = /^data:([^;]+);base64,(.+)$/s.exec(dataUri);
  if (!match) return null;
  const mimeType = match[1];
  const base64 = match[2];
  try {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return { bytes, mimeType };
  } catch (_error) {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonError("POST 요청만 허용됩니다.", 405);
  }

  let body: IsoRequestBody;
  try {
    body = await req.json();
  } catch (_error) {
    return jsonError("요청 본문이 올바른 JSON이 아닙니다.", 400);
  }

  // §7 — "원본 평면도 + GPT Clean 2D 결과를 GPT에 다시 전달". 이 함수는
  // Clean 2D 이미지 하나를 필수 입력으로 받는다(이미 검증된 단일 이미지
  // edit 패턴 재사용 — 여러 이미지 입력은 이번 범위에서 시도하지 않는다,
  // §14 "정밀 연구에 빠지지 않는다"와 일치).
  const { image } = body;
  if (typeof image !== "string" || image.trim().length === 0) {
    return jsonError("image 값이 필요합니다.", 400);
  }

  const decoded = decodeDataUri(image);
  if (!decoded) {
    return jsonError("image 값이 올바른 data URI가 아닙니다.", 400);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return jsonError("AI 3D 아이소 생성 기능이 아직 설정되지 않았습니다.", 503);
  }

  try {
    const ext = decoded.mimeType === "image/png" ? "png" : "jpg";
    const form = new FormData();
    form.append("model", OPENAI_IMAGE_MODEL);
    form.append("prompt", ISO_STYLE_PROMPT);
    form.append("image", new Blob([decoded.bytes], { type: decoded.mimeType }), `cleanplan.${ext}`);
    form.append("size", "1024x1024");
    form.append("n", "1");

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 110_000);
    let openaiResponse: Response;
    try {
      openaiResponse = await fetch(OPENAI_IMAGE_EDIT_ENDPOINT, {
        method: "POST",
        headers: { "Authorization": `Bearer ${apiKey}` },
        body: form,
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }

    if (!openaiResponse.ok) {
      console.error("OpenAI ISO 생성 요청 실패 상태:", openaiResponse.status);
      return jsonError("AI 3D 아이소 생성 요청에 실패했습니다.", 502);
    }

    const openaiPayload = await openaiResponse.json().catch(() => null);
    const b64 = openaiPayload?.data?.[0]?.b64_json;
    if (typeof b64 !== "string" || b64.length === 0) {
      return jsonError("AI 3D 아이소 생성 결과가 비어 있습니다.", 502);
    }

    return jsonResponse({
      success: true,
      image: `data:image/png;base64,${b64}`,
    });
  } catch (error) {
    console.error(
      "gpt-floorplan-iso 처리 실패:",
      error instanceof Error ? error.name : "unknown",
    );
    return jsonError("AI 3D 아이소 생성 중 오류가 발생했습니다.", 500);
  }
});
