// SPACE SHIFT - 현장미팅 문의를 접수하는 Supabase Edge Function.
//
// Flutter 앱은 Supabase 테이블에 직접 쓰지 않는다. 반드시 이 Edge
// Function을 거쳐서만 현장미팅 문의를 접수한다.
//
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY는 모든 Supabase Edge Function에
// 자동으로 주입되는 예약된 환경 변수이므로 별도 Secret 등록이 필요 없다.

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface SiteMeetingRequestBody {
  name?: unknown;
  contact?: unknown;
  visitArea?: unknown;
  preferredDateTime?: unknown;
  notes?: unknown;
  privacyAgreed?: unknown;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

/** 필수 문자열 필드를 검증하고 앞뒤 공백을 제거한다. 비어 있으면 null. */
function requiredString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse(
      { success: false, message: "POST 요청만 허용됩니다." },
      405,
    );
  }

  let body: SiteMeetingRequestBody;
  try {
    body = await req.json();
  } catch (_error) {
    return jsonResponse(
      { success: false, message: "요청 본문이 올바른 JSON이 아닙니다." },
      400,
    );
  }

  const name = requiredString(body.name);
  const contact = requiredString(body.contact);
  const visitArea = requiredString(body.visitArea);
  const preferredDateTime = requiredString(body.preferredDateTime);
  if (!name || !contact || !visitArea || !preferredDateTime) {
    return jsonResponse(
      { success: false, message: "필수 항목이 누락되었습니다." },
      400,
    );
  }
  if (body.privacyAgreed !== true) {
    return jsonResponse(
      { success: false, message: "개인정보 수집 및 이용에 동의해야 합니다." },
      400,
    );
  }
  const notes = typeof body.notes === "string" ? body.notes.trim() : "";

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(
      { success: false, message: "서버가 아직 설정되지 않았습니다." },
      503,
    );
  }

  try {
    const insertResponse = await fetch(
      `${supabaseUrl}/rest/v1/site_meeting_requests`,
      {
        method: "POST",
        headers: {
          "apikey": serviceRoleKey,
          "Authorization": `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
          "Prefer": "return=minimal",
        },
        body: JSON.stringify({
          name,
          contact,
          visit_area: visitArea,
          preferred_date_time: preferredDateTime,
          notes,
          privacy_agreed: true,
        }),
      },
    );

    if (!insertResponse.ok) {
      console.error(
        "site_meeting_requests insert 실패 상태:",
        insertResponse.status,
      );
      return jsonResponse(
        { success: false, message: "문의 접수에 실패했습니다." },
        502,
      );
    }

    return jsonResponse({ success: true });
  } catch (error) {
    console.error(
      "submit-site-meeting 처리 실패:",
      error instanceof Error ? error.name : "unknown",
    );
    return jsonResponse(
      { success: false, message: "요청 처리 중 오류가 발생했습니다." },
      500,
    );
  }
});
