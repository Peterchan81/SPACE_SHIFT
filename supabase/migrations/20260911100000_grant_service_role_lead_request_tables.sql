-- SPACE SHIFT/NOMPASS Supabase 분리(2026-09) 중 발견 — 새로 만든 프로젝트에
-- 이 저장소의 기존 마이그레이션(20260815000000)을 `supabase db push`로
-- 그대로 적용하면, 기존(Nompass와 공유하던) 프로젝트와 달리 `service_role`에
-- estimate_requests/site_meeting_requests에 대한 SELECT/INSERT/UPDATE/DELETE
-- 권한이 자동으로 부여되지 않았다(TRUNCATE/REFERENCES/TRIGGER만 기본
-- 부여됨 — Supabase 프로젝트 템플릿의 기본 권한 부여 범위가 프로젝트
-- 생성 시점에 따라 달라질 수 있는 것으로 보인다). 그 결과
-- submit-estimate/submit-site-meeting Edge Function이 "permission denied
-- for table"로 계속 실패했다.
--
-- 이 테이블들은 애초에 클라이언트가 아니라 Edge Function(Service Role)을
-- 통해서만 접근하도록 설계됐으므로(20260815000000 마이그레이션 주석 참고),
-- anon/authenticated에는 여전히 아무 권한도 주지 않고 service_role에만
-- 명시적으로 필요한 권한을 부여한다 — 앞으로 이 저장소의 마이그레이션을
-- 새 프로젝트에 적용할 때 플랫폼 기본값에 의존하지 않도록 항상 이
-- GRANT를 함께 실행한다.

grant select, insert, update, delete
  on public.estimate_requests, public.site_meeting_requests
  to service_role;
