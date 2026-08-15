-- SPACE SHIFT - 무료 예상견적 / 현장미팅 문의를 저장하는 테이블.
--
-- 두 테이블 모두 RLS를 켜두고 anon/authenticated에는 어떤 정책도 부여하지
-- 않는다. 클라이언트는 절대 이 테이블에 직접 쓰지 않고, 반드시
-- submit-estimate / submit-site-meeting Edge Function(Service Role)을
-- 거쳐서만 접근한다.

create table if not exists public.estimate_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  space_type text not null,
  approximate_area text not null,
  construction_scope text not null,
  desired_color_tone text not null,
  custom_color_tone text not null default '',
  notes text not null default ''
);

alter table public.estimate_requests enable row level security;

create table if not exists public.site_meeting_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  contact text not null,
  visit_area text not null,
  preferred_date_time text not null,
  notes text not null default '',
  privacy_agreed boolean not null default false
);

alter table public.site_meeting_requests enable row level security;
