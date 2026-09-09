// SPACE SHIFT - GPT 평면도 CAD 스타일 이미지 생성 Edge Function.
//
// V1 AI-IMAGE FLOW WO — 방향 수정: GPT는 구조화된 좌표(JSON)를 만드는
// 것이 아니라, 원본 평면도 사진의 배치/형태를 최대한 유지한 "깨끗한
// CAD 스타일 2D 평면도 이미지"를 새로 그려서 돌려준다(gpt-floorplan-
// understand의 구조화 좌표 계약과는 완전히 다른 목적 — 그 함수는
// 삭제하지 않고 R&D/대체 경로로 남겨 둔다).
//
// Flutter 앱은 OpenAI를 절대 직접 호출하지 않는다 — 이 Edge Function만
// 거친다. OpenAI Secret은 Supabase Secret OPENAI_API_KEY에서만 읽으며
// 클라이언트로 전달하거나 응답/로그에 기록하지 않는다 —
// generate-interior/index.ts와 정확히 같은 보안 패턴을 따른다.

const OPENAI_IMAGE_EDIT_ENDPOINT = "https://api.openai.com/v1/images/edits";
const OPENAI_IMAGE_MODEL = "gpt-image-1";

// V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO §5 — 정확한 계약 문구를
// 그대로 반영한다(순서도 그대로 유지 — 모델이 우선순위로 읽는다는
// 전제).
const CAD_STYLE_PROMPT =
  "Redraw the attached original floor plan as a clean CAD-style black-" +
  "and-white 2D architectural floor plan, viewed from directly above " +
  "(top-down plan view), on a plain white background. " +
  "Preserve the overall spatial layout and outer shape of the original " +
  "floor plan as closely as possible. " +
  "Do not arbitrarily change the position of the original walls, rooms, " +
  "doors, or windows. " +
  "Do not create any new room that is not present in the original. " +
  "Remove color, floor textures, decorations, watermarks, furniture, " +
  "appliances, handwriting, and dimension text from the original — " +
  "redraw the space with plain white/light-gray floor fill and clean " +
  "black wall lines instead, like a tidy professional architectural " +
  "drawing. Clearly distinguish exterior walls (thicker/darker) from " +
  "interior walls (thinner). Show every door as an opening with a door " +
  "leaf and a swing arc (standard architectural door symbol). Show every " +
  "window as an architectural window symbol (e.g. a double line) at its " +
  "wall opening. Do not invent or print any dimension/measurement text " +
  "unless it was clearly legible in the original — if the original has " +
  "no reliable dimensions, do not add any. Keep the wall/room/opening " +
  "structure visually unambiguous, since this drawing will be used as " +
  "the basis for generating a matching 3D isometric view next.";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface CadImageRequestBody {
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

  let body: CadImageRequestBody;
  try {
    body = await req.json();
  } catch (_error) {
    return jsonError("요청 본문이 올바른 JSON이 아닙니다.", 400);
  }

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
    return jsonError("AI 평면도 생성 기능이 아직 설정되지 않았습니다.", 503);
  }

  try {
    const ext = decoded.mimeType === "image/png" ? "png" : "jpg";
    const form = new FormData();
    form.append("model", OPENAI_IMAGE_MODEL);
    form.append("prompt", CAD_STYLE_PROMPT);
    form.append("image", new Blob([decoded.bytes], { type: decoded.mimeType }), `floorplan.${ext}`);
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
      console.error("OpenAI 이미지 생성 요청 실패 상태:", openaiResponse.status);
      return jsonError("AI 평면도 생성 요청에 실패했습니다.", 502);
    }

    const openaiPayload = await openaiResponse.json().catch(() => null);
    const b64 = openaiPayload?.data?.[0]?.b64_json;
    if (typeof b64 !== "string" || b64.length === 0) {
      return jsonError("AI 평면도 생성 결과가 비어 있습니다.", 502);
    }

    return jsonResponse({
      success: true,
      image: `data:image/png;base64,${b64}`,
    });
  } catch (error) {
    console.error(
      "gpt-floorplan-cad-image 처리 실패:",
      error instanceof Error ? error.name : "unknown",
    );
    return jsonError("AI 평면도 생성 중 오류가 발생했습니다.", 500);
  }
});
