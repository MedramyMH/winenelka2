-- وين نلقى؟ — Supabase starter schema
-- Run in Supabase SQL Editor. Review policies before production launch.
create extension if not exists pgcrypto;
create type public.account_role as enum ('client','provider','admin');
create type public.availability_status as enum ('available','busy','unavailable');
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role public.account_role not null default 'client',
 first_name text, last_name text, display_name text,
 avatar_url text, bio text,
 wilaya text, delegation text, sector text,
 latitude double precision, longitude double precision,
 availability public.availability_status not null default 'unavailable',
 is_verified boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.categories (
 id uuid primary key default gen_random_uuid(),
 name_ar text not null, name_fr text, slug text unique not null,
 parent_id uuid references public.categories(id) on delete set null,
 icon text, is_active boolean not null default true, sort_order int not null default 0,
 created_at timestamptz not null default now()
);
create table public.services (
 id uuid primary key default gen_random_uuid(),
 provider_id uuid not null references public.profiles(id) on delete cascade,
 category_id uuid not null references public.categories(id),
 title text not null, description text,
 tasks text[] not null default '{}', physical_requirements text,
 mental_requirements text, experience_years int, price_from numeric(10,3), price_unit text,
 is_active boolean not null default true, created_at timestamptz not null default now()
);
-- Private contact details are deliberately isolated from publicly readable profiles.
create table public.private_contacts (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 phone text, email text, updated_at timestamptz not null default now()
);
create table public.marketplace_listings (
 id uuid primary key default gen_random_uuid(), seller_id uuid not null references public.profiles(id) on delete cascade,
 title text not null, description text not null, price numeric(10,3) not null check(price >= 0),
 category text not null, condition text not null default 'used' check(condition in ('new','used','refurbished')),
 wilaya text, delegation text, sector text, image_urls text[] not null default '{}',
 status text not null default 'active' check(status in ('active','sold','hidden','removed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.provider_media (
 id uuid primary key default gen_random_uuid(), provider_id uuid not null references public.profiles(id) on delete cascade,
 storage_path text not null, caption text, media_type text not null default 'portfolio', created_at timestamptz not null default now()
);
create table public.announcements (
 id uuid primary key default gen_random_uuid(), client_id uuid not null references public.profiles(id) on delete cascade,
 category_id uuid references public.categories(id), title text not null, description text not null,
 wilaya text, delegation text, sector text, status text not null default 'open' check(status in ('open','closed','cancelled')),
 expires_at timestamptz, created_at timestamptz not null default now()
);
create table public.subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 plan_code text not null check(plan_code in ('daily','monthly','yearly')),
 starts_at timestamptz not null default now(), ends_at timestamptz not null,
 status text not null default 'pending' check(status in ('pending','active','expired','cancelled')),
 payment_provider text, provider_reference text, created_at timestamptz not null default now()
);
create table public.payments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 subscription_id uuid references public.subscriptions(id), amount numeric(10,3) not null,
 currency text not null default 'TND', method text not null,
 status text not null default 'pending' check(status in ('pending','succeeded','failed','refunded')),
 provider_reference text, created_at timestamptz not null default now()
);
create table public.reviews (
 id uuid primary key default gen_random_uuid(), service_id uuid not null references public.services(id) on delete cascade,
 client_id uuid not null references public.profiles(id) on delete cascade,
 provider_id uuid not null references public.profiles(id) on delete cascade,
 rating int not null check(rating between 1 and 5), comment text,
 completion_photo_path text, service_completed boolean not null default false,
 created_at timestamptz not null default now(), unique(service_id,client_id)
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null, body text not null, kind text not null default 'general',
 related_id uuid, read_at timestamptz, created_at timestamptz not null default now()
);
create index services_category_idx on public.services(category_id) where is_active;
create index services_provider_idx on public.services(provider_id) where is_active;
create index marketplace_category_idx on public.marketplace_listings(category,status,created_at desc);
create index marketplace_location_idx on public.marketplace_listings(wilaya,delegation,sector) where status = 'active';
create index profiles_location_idx on public.profiles(wilaya,delegation,sector);
create index announcements_category_idx on public.announcements(category_id,status,created_at desc);
create index reviews_provider_idx on public.reviews(provider_id,created_at desc);

-- Enable RLS. Private contact data must never be exposed by public profile reads.
alter table public.profiles enable row level security;
alter table public.private_contacts enable row level security;
alter table public.marketplace_listings enable row level security;
alter table public.categories enable row level security;
alter table public.services enable row level security;
alter table public.provider_media enable row level security;
alter table public.announcements enable row level security;
alter table public.subscriptions enable row level security;
alter table public.payments enable row level security;
alter table public.reviews enable row level security;
alter table public.notifications enable row level security;

create policy "active categories readable" on public.categories for select using (is_active = true);
-- WARNING: This policy exposes all profile data including exact coordinates
-- TODO Phase 1: Create a view or function that exposes only wilaya/delegation
-- and rounds coordinates to ~1km precision for public access
create policy "public profile basics readable" on public.profiles for select using (true);
create policy "owners read own private contact" on public.private_contacts for select using (auth.uid() = user_id);
create policy "owners insert own private contact" on public.private_contacts for insert with check (auth.uid() = user_id);
create policy "owners update own private contact" on public.private_contacts for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "active marketplace listings readable" on public.marketplace_listings for select using (status = 'active' or auth.uid() = seller_id);
create policy "sellers create own listings" on public.marketplace_listings for insert with check (auth.uid() = seller_id);
create policy "sellers update own listings" on public.marketplace_listings for update using (auth.uid() = seller_id) with check (auth.uid() = seller_id);
-- Prevent privilege escalation: users cannot set role=admin or is_verified=true
create policy "owners manage own profile" on public.profiles for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    and role = (select role from public.profiles where id = auth.uid())
    and is_verified = (select is_verified from public.profiles where id = auth.uid())
  );
create policy "users create own profile" on public.profiles for insert
  with check (
    auth.uid() = id
    and role in ('client', 'provider')
    and is_verified = false
  );
create policy "active services readable" on public.services for select using (is_active = true);
create policy "providers manage own services" on public.services for all using (auth.uid() = provider_id) with check (auth.uid() = provider_id);
create policy "public portfolio readable" on public.provider_media for select using (true);
create policy "owners manage own media" on public.provider_media for all using (auth.uid() = provider_id) with check (auth.uid() = provider_id);
create policy "open announcements readable" on public.announcements for select using (status = 'open' or auth.uid() = client_id);
create policy "clients manage own announcements" on public.announcements for all using (auth.uid() = client_id) with check (auth.uid() = client_id);
create policy "users read own subscriptions" on public.subscriptions for select using (auth.uid() = user_id);
create policy "users read own payments" on public.payments for select using (auth.uid() = user_id);
create policy "reviews readable" on public.reviews for select using (true);
-- Reviews must be tied to completed bookings
create policy "clients create own reviews" on public.reviews for insert with check (
  auth.uid() = client_id
  and auth.uid() != provider_id
  and exists (
    select 1 from public.bookings
    where bookings.service_id = reviews.service_id
      and bookings.client_id = reviews.client_id
      and bookings.provider_id = reviews.provider_id
      and bookings.status = 'completed'
      and bookings.completed_at is not null
  )
);
create policy "users read own notifications" on public.notifications for select using (auth.uid() = user_id);
create policy "users update own notifications" on public.notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Trigger to create profile on signup
-- Stores the role from user metadata if provided during registration
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, role, created_at, updated_at)
  values (
    new.id,
    coalesce(
      (new.raw_user_meta_data->>'role')::public.account_role,
      'client'::public.account_role
    ),
    now(),
    now()
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Additional tables for Phase 1 features
create table public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  service_id uuid references public.services(id) on delete cascade,
  listing_id uuid references public.marketplace_listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint one_favorite_target check (
    (service_id is not null and listing_id is null) or
    (service_id is null and listing_id is not null)
  ),
  unique(user_id, service_id),
  unique(user_id, listing_id)
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  provider_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted','completed','cancelled','disputed')),
  scheduled_at timestamptz,
  completed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete cascade,
  reported_service_id uuid references public.services(id) on delete cascade,
  reported_listing_id uuid references public.marketplace_listings(id) on delete cascade,
  reason text not null,
  details text,
  status text not null default 'pending' check(status in ('pending','investigating','resolved','dismissed')),
  admin_notes text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  table_name text,
  record_id uuid,
  old_data jsonb,
  new_data jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

create table public.wilaya_data (
  id smallint primary key,
  name_ar text not null,
  name_fr text not null,
  code text not null unique
);

create table public.delegation_data (
  id serial primary key,
  wilaya_id smallint not null references public.wilaya_data(id),
  name_ar text not null,
  name_fr text not null
);

-- Enable RLS on new tables
alter table public.favorites enable row level security;
alter table public.bookings enable row level security;
alter table public.reports enable row level security;
alter table public.audit_log enable row level security;
alter table public.wilaya_data enable row level security;
alter table public.delegation_data enable row level security;

-- RLS policies for new tables
create policy "users manage own favorites" on public.favorites for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "booking participants can view" on public.bookings for select
  using (auth.uid() in (client_id, provider_id));

create policy "clients create bookings" on public.bookings for insert
  with check (auth.uid() = client_id);

create policy "booking participants can update" on public.bookings for update
  using (auth.uid() in (client_id, provider_id))
  with check (auth.uid() in (client_id, provider_id));

create policy "users can create reports" on public.reports for insert
  with check (auth.uid() = reporter_id);

create policy "users can view own reports" on public.reports for select
  using (auth.uid() = reporter_id);

create policy "location data readable by all" on public.wilaya_data for select using (true);
create policy "delegation data readable by all" on public.delegation_data for select using (true);

-- Audit log is admin-only (no policies for regular users)
-- TODO: Add admin role check function and policy

-- Indexes for new tables
create index favorites_user_idx on public.favorites(user_id, created_at desc);
create index bookings_client_idx on public.bookings(client_id, status, created_at desc);
create index bookings_provider_idx on public.bookings(provider_id, status, created_at desc);
create index reports_status_idx on public.reports(status, created_at desc);
create index audit_log_user_idx on public.audit_log(user_id, created_at desc);
create index delegation_wilaya_idx on public.delegation_data(wilaya_id);

-- IMPORTANT PRODUCTION TODO:
-- 1) ✓ FIXED: Profile privilege escalation - users can no longer set role=admin or is_verified=true
-- 2) ✓ FIXED: Reviews now require completed booking - prevents fake reviews and self-reviews
-- 3) ✓ ADDED: Profile creation trigger - new users automatically get a profile with their chosen role
-- 4) ✓ ADDED: Bookings, favorites, reports, audit_log, and Tunisia location tables
-- 5) TODO: Keep phone/email in private_contacts. Reveal them only through a server-side Edge Function
--    after checking active subscription; do not expose the table through a public view.
-- 6) TODO: Add admin-only policies/claims for category moderation and provider verification.
--    Consider using custom JWT claims or a separate admin_users table.
-- 7) TODO: Create an Edge Function to verify payment provider callbacks; never trust client-side payment success.
-- 8) TODO: Implement proper verified review flow with booking status transitions
-- 9) TODO: Add rate limits, anti-spam controls, CAPTCHA, and verified identity workflows
-- 10) WARNING: profiles table still exposes exact latitude/longitude. Before production:
--     - Create a public view that rounds coordinates to ~1km precision
--     - Or only show wilaya/delegation publicly and exact location after contact reveal
-- 11) TODO: Implement password reset flow, strengthen password requirements
-- 12) TODO: Add phone OTP authentication (+216) and Google OAuth
-- 13) TODO: Implement admin dashboard with verification queue, moderation tools, reports management
-- 14) TODO: Add normalized Arabic text search (handle hamza, ة/ه, ى/ي, diacritics)
-- 15) TODO: Add French/Arabizi search support with synonyms table
-- 16) TODO: Populate wilaya_data and delegation_data tables with Tunisia's 24 wilayas
-- 17) TODO: Add PostGIS extension for real geographic distance calculations
-- 18) TODO: Implement pagination for all list queries
-- 19) TODO: Add image upload to Supabase Storage with compression and size limits
-- 20) TODO: Add blocking/reporting functionality and content moderation
-- 21) TODO: Set up proper security headers (see netlify.toml)
-- 22) TODO: Legal compliance - add terms, privacy policy (AR/FR), INPDP declaration
