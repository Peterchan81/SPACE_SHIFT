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

// WO092 §1 — 실기 Tab 결과가 "지나치게 단순화됨"으로 불합격 판정을
// 받아, 구조 보존을 훨씬 더 구체적이고 강하게 요구하도록 강화한다.
// 순서를 그대로 유지한다(모델이 앞쪽 문장을 우선순위로 읽는다는 전제는
// WO091부터 유지해 온 가정).
const CAD_STYLE_PROMPT =
  "Redraw the attached original floor plan as a clean CAD-style black-" +
  "and-white 2D architectural floor plan, viewed from directly above " +
  "(top-down plan view), on a plain white background. " +
  "This must be a faithful trace of the original, not a redesigned or " +
  "simplified version — preserve the EXACT overall spatial layout and " +
  "outer outline of the original floor plan, including every small " +
  "notch, jog, protrusion, or offset in the exterior outline and every " +
  "interior wall. Do not straighten, merge, simplify, or omit any wall " +
  "segment, room, or outline detail, even small ones. " +
  "Preserve the exact number of rooms and their exact positions and " +
  "shapes — do not merge two rooms into one, do not split one room into " +
  "two, and do not change any room's size or proportions. " +
  "Preserve every structural element visible in the original at its " +
  "exact original position and shape, including (when present): " +
  "staircases (draw the stair-tread hatching/lines), elevator shafts, " +
  "bathrooms, walk-in closets/dressing rooms, balconies, utility rooms, " +
  "and entryways — do not remove, relabel, resize, or relocate any of " +
  "them. " +
  "Do not arbitrarily change the position of the original walls, rooms, " +
  "doors, or windows. Do not create any new room, wall, door, or window " +
  "that is not present in the original. " +
  "Remove color, floor textures, decorations, watermarks, furniture, " +
  "appliances, handwriting, and dimension text from the original — " +
  "redraw the space with plain white/light-gray floor fill and clean " +
  "black wall lines instead, like a tidy professional architectural " +
  "drawing. Clearly distinguish exterior walls (thicker/darker) from " +
  "interior walls (thinner), matching which walls are exterior/interior " +
  "in the original. Show every door as an opening with a door leaf and " +
  "a swing arc (standard architectural door symbol), at the same wall " +
  "position as in the original. Show every window as an architectural " +
  "window symbol (e.g. a double line) at its original wall opening. " +
  "Do not invent or print any dimension/measurement text unless it was " +
  "clearly legible in the original — if the original has no reliable " +
  "dimensions, do not add any. Keep the wall/room/opening structure " +
  "visually unambiguous, since this drawing will be used as the basis " +
  "for generating a matching 3D isometric view next, and the room " +
  "count/layout must match the original exactly.";

/// WO092 §1 — 원본이 정사각형이 아닌데 항상 1024x1024로 강제하면
/// GPT가 캔버스에 맞추려고 레이아웃을 임의로 단순화/왜곡하는 것으로
/// 보인다(실기 Tab 결과 불합격의 유력한 원인). 원본 픽셀 비율에 맞는
/// 출력 크기를 골라 그런 왜곡 압력을 줄인다. gpt-image-1가 지원하는
/// 크기는 정사각형/가로형/세로형 세 가지뿐이라 그중 가장 가까운 것을
/// 고른다(비율 자체를 정확히 재현하지는 못하지만 정사각형 강제보다는
/// 훨씬 낫다).
function pickOutputSize(width: number, height: number): string {
  if (width <= 0 || height <= 0) return "1024x1024";
  const ratio = width / height;
  if (ratio > 1.15) return "1536x1024";
  if (ratio < 1 / 1.15) return "1024x1536";
  return "1024x1024";
}

/** PNG/JPEG 바이트에서 (width, height)를 읽는다 — 실패하면 null. */
function sniffImageDimensions(
  bytes: Uint8Array,
  mimeType: string,
): { width: number; height: number } | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (mimeType === "image/png" && bytes.length >= 24) {
    const isPng =
      bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
    if (isPng) {
      return { width: view.getUint32(16), height: view.getUint32(20) };
    }
  }
  if (mimeType === "image/jpeg" || mimeType === "image/jpg") {
    // SOF(0xFFC0~0xFFCF, 마커 0xC4/0xC8/0xCC 제외) 세그먼트를 찾아
    // height/width(빅엔디언, 각 2바이트)를 읽는다.
    let offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] !== 0xff) break;
      const marker = bytes[offset + 1];
      if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd9)) {
        offset += 2;
        continue;
      }
      const segmentLength = view.getUint16(offset + 2);
      const isSof =
        marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
      if (isSof) {
        return { width: view.getUint16(offset + 7), height: view.getUint16(offset + 5) };
      }
      offset += 2 + segmentLength;
    }
  }
  return null;
}

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
    const dimensions = sniffImageDimensions(decoded.bytes, decoded.mimeType);
    const size = dimensions
      ? pickOutputSize(dimensions.width, dimensions.height)
      : "1024x1024";
    const form = new FormData();
    form.append("model", OPENAI_IMAGE_MODEL);
    form.append("prompt", CAD_STYLE_PROMPT);
    form.append("image", new Blob([decoded.bytes], { type: decoded.mimeType }), `floorplan.${ext}`);
    form.append("size", size);
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
