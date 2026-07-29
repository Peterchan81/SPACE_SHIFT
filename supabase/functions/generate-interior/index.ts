// ASON Space - AI 인테리어 생성 요청을 받는 Supabase Edge Function.
//
// Flutter 앱은 Fal.ai 등 AI 업체를 절대 직접 호출하지 않는다.
// 반드시 이 Edge Function을 거쳐서만 AI 이미지 생성을 요청한다.
//
// 이번 단계에서는 실제 Fal.ai 호출을 구현하지 않는다.
// 요청 형식 검증(POST/CORS/JSON/style/image)과 더미(Mock) JSON 응답만
// 반환하는 뼈대 구조만 만든다.
//
// TODO(향후 실제 AI 연동 시 아래 순서로 교체한다):
//   1. 지금의 Mock 응답(success/provider/"mock"/message) 코드를 제거한다.
//   2. Deno.env.get("FAL_API_KEY")로 Secret(Fal.ai API Key)을 읽는다.
//      (Secret은 `supabase secrets set FAL_API_KEY=...`로 미리 등록해 둔다.)
//   3. Fal.ai 이미지 편집 API에 style, image(Base64 또는 URL)를 전달해
//      실제 생성을 요청한다.
//   4. 생성된 이미지 URL(또는 바이트)을 받아
//      { success: true, provider: "fal", imageUrl: "..." } 형태로 응답한다.
//   5. Fal.ai 호출이 실패하면 success:false 응답으로 안전하게 변환해
//      반환한다(Edge Function이 예외로 죽지 않도록 한다).

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

  // image 존재 확인. Base64 문자열 또는 URL 문자열 모두 허용한다.
  if (typeof image !== "string" || image.trim().length === 0) {
    return jsonResponse(
      { success: false, message: "image 값이 필요합니다." },
      400,
    );
  }

  try {
    // ------------------------------------------------------------------
    // 이번 단계: 실제 AI 호출 없이 더미 응답만 반환한다.
    // 위 파일 상단 TODO를 참고해 추후 Fal.ai 실제 연동으로 교체한다.
    // ------------------------------------------------------------------
    return jsonResponse({
      success: true,
      provider: "mock",
      message: "Edge Function 준비 완료",
      imageUrl: null,
    });
  } catch (error) {
    // Fal.ai 연동 이후에는 실제 호출 실패 시에도 이 블록에서
    // success:false 응답으로 안전하게 변환해, 함수가 예외로 죽지 않게 한다.
    console.error("generate-interior 처리 중 오류:", error);
    return jsonResponse(
      { success: false, message: "이미지 생성 중 오류가 발생했습니다." },
      500,
    );
  }
});
