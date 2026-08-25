
create extension if not exists pgcrypto;
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade, role text not null default 'customer' check(role in('customer','admin')), full_name text, created_at timestamptz not null default now());
create table if not exists public.products(id uuid primary key default gen_random_uuid(),slug text unique not null,name text not null,category text not null check(category in('T-Shirts','Polos')),description text,price numeric(10,2) not null check(price>=0),color text not null,sizes text[] not null default '{M,L}',stock integer not null default 0 check(stock>=0),active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.product_images(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,url text not null,sort_order integer not null default 0,created_at timestamptz not null default now());
create table if not exists public.coupons(id uuid primary key default gen_random_uuid(),code text unique not null,kind text not null check(kind in('percent','fixed')),value numeric(10,2) not null check(value>=0),minimum_order numeric(10,2) not null default 0,usage_limit integer,usage_count integer not null default 0,active boolean not null default true,expires_at timestamptz,created_at timestamptz not null default now());
create table if not exists public.settings(key text primary key,value jsonb not null);
create table if not exists public.orders(id uuid primary key default gen_random_uuid(),order_number text unique not null,customer_name text not null,phone text not null,email text,district text not null,address text not null,delivery_area text not null check(delivery_area in('dhaka','outside')),payment_method text not null check(payment_method in('cod','bkash','nagad','online')),payment_status text not null default 'pending' check(payment_status in('pending','paid','failed','cancelled')),status text not null default 'new' check(status in('new','confirmed','packed','shipped','delivered','returned','cancelled')),subtotal numeric(10,2) not null,delivery_fee numeric(10,2) not null,discount numeric(10,2) not null default 0,total numeric(10,2) not null,notes text,coupon_code text,created_at timestamptz not null default now());
create table if not exists public.order_items(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,product_id uuid not null references public.products(id),product_name text not null,unit_price numeric(10,2) not null,size text not null,color text not null,qty integer not null check(qty>0),subtotal numeric(10,2) generated always as (unit_price*qty) stored);

insert into public.settings(key,value) values
('store','{"name":"VELUSH","currency":"BDT"}'),
('shipping','{"insideDhaka":80,"outsideDhaka":130,"freeAbove":3500}'),
('returns','{"policy":"The product must not be damaged for return/exchange eligibility."}'),
('contact','{"email":"","phone":""}'),
('storeNote','') on conflict(key) do nothing;

insert into public.products(slug,name,category,price,color,sizes,stock,active) values
('check-ribbed-polo','Check Ribbed Polo','Polos',899,'Check','{M,L}',20,true),
('white-ribbed-polo','White Ribbed Polo','Polos',899,'White','{M,L}',20,true),
('navy-ribbed-polo','Navy Ribbed Polo','Polos',899,'Navy','{M,L}',20,true),
('khaki-tshirt','Khaki T-shirt','T-Shirts',799,'Khaki','{M,L}',20,true),
('one-piece-tshirt','One Piece T-shirt','T-Shirts',799,'White','{M,L}',20,true),
('navy-tshirt','Navy T-shirt','T-Shirts',799,'Navy','{M,L}',20,true),
('maroon-tshirt','Maroon T-shirt','T-Shirts',799,'Maroon','{M,L}',20,true)
on conflict(slug) do update set name=excluded.name,category=excluded.category,price=excluded.price,color=excluded.color,sizes=excluded.sizes,active=true;

alter table public.profiles enable row level security;alter table public.products enable row level security;alter table public.product_images enable row level security;alter table public.orders enable row level security;alter table public.order_items enable row level security;alter table public.coupons enable row level security;alter table public.settings enable row level security;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.profiles where id=auth.uid() and role='admin')$$;
create policy "profiles own read" on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy "public active product read" on public.products for select using(active=true or public.is_admin());
create policy "admin product write" on public.products for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public product images read" on public.product_images for select using(true);
create policy "admin product images write" on public.product_images for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin orders read" on public.orders for select to authenticated using(public.is_admin());
create policy "admin orders update" on public.orders for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin order items read" on public.order_items for select to authenticated using(public.is_admin());
create policy "admin coupons manage" on public.coupons for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public settings read" on public.settings for select using(true);
create policy "admin settings manage" on public.settings for all to authenticated using(public.is_admin()) with check(public.is_admin());

create or replace function public.create_order_secure(p_customer_name text,p_phone text,p_email text,p_district text,p_address text,p_delivery_area text,p_payment_method text,p_notes text,p_coupon_code text,p_items jsonb)
returns table(order_id uuid,order_number text,subtotal numeric,delivery_fee numeric,discount numeric,total numeric,payment_status text)
language plpgsql security definer set search_path=public as $$
declare line jsonb; v_product products%rowtype; v_qty int; v_sub numeric:=0; v_ship numeric:=0; v_discount numeric:=0; v_total numeric:=0; v_order uuid; v_number text; v_coupon coupons%rowtype; v_code text:=nullif(upper(trim(coalesce(p_coupon_code,''))),''); v_free numeric:=3500; v_dhaka numeric:=80; v_outside numeric:=130; v_payment_status text:='pending';
begin
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 then raise exception 'Cart is empty'; end if;
 if length(trim(coalesce(p_customer_name,'')))<2 then raise exception 'Name is required'; end if;
 if length(trim(coalesce(p_phone,'')))<7 then raise exception 'Valid phone is required'; end if;
 if length(trim(coalesce(p_district,'')))<2 or length(trim(coalesce(p_address,'')))<5 then raise exception 'Complete delivery address is required'; end if;
 if p_delivery_area not in('dhaka','outside') then raise exception 'Invalid delivery area'; end if;
 if p_payment_method not in('cod','bkash','nagad','online') then raise exception 'Invalid payment method'; end if;
 select coalesce((value->>'insideDhaka')::numeric,80),coalesce((value->>'outsideDhaka')::numeric,130),coalesce((value->>'freeAbove')::numeric,3500) into v_dhaka,v_outside,v_free from public.settings where key='shipping';
 for line in select * from jsonb_array_elements(p_items) loop
  select * into v_product from public.products where id=(line->>'product_id')::uuid for update;
  if not found or not v_product.active then raise exception 'Product unavailable'; end if;
  if not ((line->>'size')=any(v_product.sizes)) then raise exception 'Selected size unavailable for %',v_product.name; end if;
  v_qty := (line->>'qty')::int; if v_qty<1 or v_qty>100 then raise exception 'Invalid quantity'; end if;
  if v_product.stock<v_qty then raise exception 'Insufficient stock for %',v_product.name; end if;
  v_sub := v_sub + v_product.price*v_qty;
 end loop;
 if v_code is not null then
  select * into v_coupon from public.coupons where code=v_code and active=true and (expires_at is null or expires_at>now()) for update;
  if not found then raise exception 'Coupon is invalid or expired'; end if;
  if v_coupon.usage_limit is not null and v_coupon.usage_count>=v_coupon.usage_limit then raise exception 'Coupon usage limit reached'; end if;
  if v_sub<v_coupon.minimum_order then raise exception 'Minimum order for coupon is %',v_coupon.minimum_order; end if;
  if v_coupon.kind='percent' then v_discount:=round(v_sub*v_coupon.value/100,2); else v_discount:=v_coupon.value; end if;
  if v_discount>v_sub then v_discount:=v_sub; end if;
 end if;
 if v_sub-v_discount>v_free then v_ship:=0; elsif p_delivery_area='dhaka' then v_ship:=v_dhaka; else v_ship:=v_outside; end if;
 v_total:=v_sub-v_discount+v_ship;
 v_number:='VEL-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 if p_payment_method<>'cod' then v_payment_status:='pending'; end if;
 insert into public.orders(order_number,customer_name,phone,email,district,address,delivery_area,payment_method,payment_status,status,subtotal,delivery_fee,discount,total,notes,coupon_code) values(v_number,trim(p_customer_name),trim(p_phone),nullif(trim(coalesce(p_email,'')),''),trim(p_district),trim(p_address),p_delivery_area,p_payment_method,v_payment_status,'new',v_sub,v_ship,v_discount,v_total,nullif(trim(coalesce(p_notes,'')),''),v_code) returning id into v_order;
 for line in select * from jsonb_array_elements(p_items) loop
  select * into v_product from public.products where id=(line->>'product_id')::uuid for update; v_qty:=(line->>'qty')::int;
  update public.products set stock=stock-v_qty,updated_at=now() where id=v_product.id and stock>=v_qty; if not found then raise exception 'Stock changed for %',v_product.name; end if;
  insert into public.order_items(order_id,product_id,product_name,unit_price,size,color,qty) values(v_order,v_product.id,v_product.name,v_product.price,line->>'size',v_product.color,v_qty);
 end loop;
 if v_code is not null then update public.coupons set usage_count=usage_count+1 where id=v_coupon.id; end if;
 return query select v_order,v_number,v_sub,v_ship,v_discount,v_total,v_payment_status;
end $$;

revoke all on function public.create_order_secure(text,text,text,text,text,text,text,text,text,jsonb) from public,anon,authenticated;

insert into storage.buckets(id,name,public) values('product-images','product-images',true) on conflict(id) do update set public=true;
create policy "public product image read" on storage.objects for select using(bucket_id='product-images');
create policy "admin product image insert" on storage.objects for insert to authenticated with check(bucket_id='product-images' and public.is_admin());
create policy "admin product image update" on storage.objects for update to authenticated using(bucket_id='product-images' and public.is_admin()) with check(bucket_id='product-images' and public.is_admin());
create policy "admin product image delete" on storage.objects for delete to authenticated using(bucket_id='product-images' and public.is_admin());
