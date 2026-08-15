// SPACE SHIFT - AI 인테리어 생성 요청을 받는 Supabase Edge Function.
//
// Flutter 앱은 Fal.ai 등 AI 업체를 절대 직접 호출하지 않는다.
// 반드시 이 Edge Function을 거쳐서만 AI 이미지 생성을 요청한다.
//
// Fal.ai Secret은 Supabase Secret FAL_KEY에서만 읽으며 클라이언트로
// 전달하거나 응답/로그에 기록하지 않는다.

const FAL_ENDPOINT = "https://fal.run/fal-ai/flux-pro/kontext";
const ALLOWED_STYLES = new Set([
  "모던",
  "미니멀",
  "북유럽",
  "호텔",
  "따뜻한 우드",
]);

const STYLE_PROMPTS: Record<string, string> = {
  "모던": "a refined modern interior with clean lines and contemporary furniture",
  "미니멀": "a calm minimalist interior with uncluttered surfaces and simple furniture",
  "북유럽": "a bright Scandinavian interior with soft neutral colors and natural textures",
  "호텔": "a luxurious hotel-style interior with elegant lighting and premium finishes",
  "따뜻한 우드": "a warm wood interior with natural timber finishes and cozy lighting",
};

/** 모든 응답에 공통으로 붙이는 CORS 헤더. Flutter Web에서 호출할 때 필요하다. */
const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * 요청 본문 타입.
 *
 * image는 Base64로 인코딩한 이미지 문자열과, (향후 Storage 등에 먼저
 * 업로드했을 경우의) 접근 가능한 URL 문자열을 모두 받을 수 있는 구조로
 * 설계한다. 실제 형식 판별/검증은 Fal.ai 연동 시점에 구체화한다.
 */
interface GenerateInteriorRequestBody {
  style?: unknown;
  image?: unknown;
}

/** 성공/실패 여부와 관계없이 동일한 형태로 JSON 응답을 만든다. */
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req: Request) => {
  // 브라우저(Flutter Web 포함)가 실제 POST 전에 보내는 CORS 사전 요청 처리.
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // 이번 단계에서는 POST만 허용한다.
  if (req.method !== "POST") {
    return jsonResponse(
      { success: false, message: "POST 요청만 허용됩니다." },
      405,
    );
  }

  // JSON Body 파싱. 형식이 올바르지 않으면 400으로 안전하게 응답한다.
  let body: GenerateInteriorRequestBody;
  try {
    body = await req.json();
  } catch (_error) {
    return jsonResponse(
      { success: false, message: "요청 본문이 올바른 JSON이 아닙니다." },
      400,
    );
  }

  const { style, image } = body;

  // style 존재 확인.
  if (typeof style !== "string" || style.trim().length === 0) {
    return jsonResponse(
      { success: false, message: "style 값이 필요합니다." },
      400,
    );
  }
  if (!ALLOWED_STYLES.has(style)) {
    return jsonResponse(
      { success: false, message: "지원하지 않는 스타일입니다." },
      400,
    );
  }

  // image 존재 확인. Base64 문자열 또는 URL 문자열 모두 허용한다.
  if (typeof image !== "string" || image.trim().length === 0) {
    return jsonResponse(
      { success: false, message: "image 값이 필요합니다." },
      400,
    );
  }

  try {
    const falKey = Deno.env.get("FAL_KEY");
    if (!falKey) {
      return jsonResponse(
        { success: false, message: "AI 서비스가 아직 설정되지 않았습니다." },
        503,
      );
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 110_000);
    let falResponse: Response;
    try {
      falResponse = await fetch(FAL_ENDPOINT, {
        method: "POST",
        headers: {
          "Authorization": `Key ${falKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          prompt:
            `Transform this room into ${STYLE_PROMPTS[style]}. ` +
            "Preserve the exact room structure, camera angle, walls, windows, doors, ceiling, floor plan, and perspective. " +
            "Change only furniture, materials, colors, lighting, and decor. Keep it photorealistic and buildable.",
          image_url: image,
          guidance_scale: 3.5,
          num_images: 1,
          output_format: "png",
          safety_tolerance: "2",
          enhance_prompt: false,
        }),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }

    const falPayload = await falResponse.json().catch(() => null);
    if (!falResponse.ok) {
      console.error("Fal.ai 요청 실패 상태:", falResponse.status);
      return jsonResponse(
        { success: false, message: "AI 이미지 생성 요청에 실패했습니다." },
        502,
      );
    }

    const imageUrl = falPayload?.images?.[0]?.url;
    if (typeof imageUrl !== "string" || imageUrl.length === 0) {
      return jsonResponse(
        { success: false, message: "생성된 이미지 결과가 없습니다." },
        502,
      );
    }

    return jsonResponse({
      success: true,
      provider: "fal",
      imageUrl,
    });
  } catch (error) {
    console.error(
      "generate-interior 처리 실패:",
      error instanceof Error ? error.name : "unknown",
    );
    return jsonResponse(
      { success: false, message: "이미지 생성 중 오류가 발생했습니다." },
      500,
    );
  }
});
