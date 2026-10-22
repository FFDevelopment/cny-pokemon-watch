-- CNY Pokémon Watch production schema (dedicated Supabase project only).
-- Run once in the NEW CNY Supabase project, not the AFewBuds project.
-- Admin must be promoted by the project owner after verified email signup.
CREATE SCHEMA IF NOT EXISTS cny_private;
REVOKE ALL ON SCHEMA cny_private FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS public.cny_profiles (
 id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 username text NOT NULL UNIQUE,
 status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','disabled')),
 role text NOT NULL DEFAULT 'member' CHECK (role IN ('member','admin')),
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT cny_username_shape CHECK(username ~ '^[A-Za-z0-9_]{3,24}$')
);
CREATE UNIQUE INDEX IF NOT EXISTS cny_profiles_username_ci ON public.cny_profiles (lower(username));
CREATE TABLE IF NOT EXISTS public.cny_products (
 slug text PRIMARY KEY CHECK(slug ~ '^[a-z0-9-]+$'),
 name text NOT NULL,
 expansion text NOT NULL,
 category text NOT NULL CHECK(category IN ('booster_box','booster_bundle','etb','tin','collection','blister','other')),
 release_date date,
 official_url text CHECK(official_url IS NULL OR official_url ~ '^https://'),
 available boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.cny_stores (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 retailer text NOT NULL,
 name text NOT NULL,
 town text NOT NULL,
 address text,
 website text CHECK(website IS NULL OR website ~ '^https://'),
 online boolean NOT NULL DEFAULT false,
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.cny_offers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 product_slug text NOT NULL REFERENCES public.cny_products(slug) ON DELETE CASCADE,
 store_id uuid NOT NULL REFERENCES public.cny_stores(id) ON DELETE CASCADE,
 product_url text CHECK(product_url IS NULL OR product_url ~ '^https://'),
 price numeric(10,2) CHECK(price IS NULL OR price >= 0),
 stock_status text NOT NULL DEFAULT 'unknown' CHECK(stock_status IN ('unknown','in_stock','out_of_stock')),
 verified_at timestamptz,
 verification_method text CHECK(verification_method IS NULL OR verification_method IN ('retailer_api','verified_feed','admin_confirmation')),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(product_slug, store_id, product_url)
);
CREATE TABLE IF NOT EXISTS public.cny_watches (
 user_id uuid NOT NULL REFERENCES public.cny_profiles(id) ON DELETE CASCADE,
 product_slug text NOT NULL REFERENCES public.cny_products(slug) ON DELETE CASCADE,
 max_price numeric(10,2) CHECK(max_price IS NULL OR (max_price > 0 AND max_price <= 100000)),
 towns text[] NOT NULL DEFAULT '{}'::text[],
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id, product_slug)
);
CREATE TABLE IF NOT EXISTS public.cny_notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES public.cny_profiles(id) ON DELETE CASCADE,
 offer_id uuid NOT NULL REFERENCES public.cny_offers(id) ON DELETE CASCADE,
 title text NOT NULL,
 body text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 read_at timestamptz
);
CREATE INDEX IF NOT EXISTS cny_notifications_user_idx ON public.cny_notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS cny_offers_product_idx ON public.cny_offers(product_slug);
CREATE INDEX IF NOT EXISTS cny_watches_product_idx ON public.cny_watches(product_slug);

CREATE OR REPLACE FUNCTION cny_private.is_approved() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT EXISTS(SELECT 1 FROM public.cny_profiles WHERE id=(SELECT auth.uid()) AND status='approved')
$$;
CREATE OR REPLACE FUNCTION cny_private.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT EXISTS(SELECT 1 FROM public.cny_profiles WHERE id=(SELECT auth.uid()) AND status='approved' AND role='admin')
$$;
GRANT USAGE ON SCHEMA cny_private TO authenticated;
GRANT EXECUTE ON FUNCTION cny_private.is_approved() TO authenticated;
GRANT EXECUTE ON FUNCTION cny_private.is_admin() TO authenticated;

-- Auth metadata only supplies the proposed username, never role or approval.
CREATE OR REPLACE FUNCTION cny_private.create_profile() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE proposed text;
BEGIN
 proposed := new.raw_user_meta_data->>'username';
 IF proposed IS NULL OR proposed !~ '^[A-Za-z0-9_]{3,24}$' THEN
   RAISE EXCEPTION 'Username must have 3-24 letters, digits, or underscores';
 END IF;
 INSERT INTO public.cny_profiles(id,username,status,role)
 VALUES(new.id,proposed,'pending','member');
 RETURN new;
END;
$$;
DROP TRIGGER IF EXISTS cny_profile_on_signup ON auth.users;
CREATE TRIGGER cny_profile_on_signup AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION cny_private.create_profile();

-- Update timestamp and create in-app alerts ONLY on new, recently verified in-stock evidence.
CREATE OR REPLACE FUNCTION cny_private.offer_notify() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF new.stock_status='in_stock'
    AND new.verified_at IS NOT NULL
    AND new.verified_at BETWEEN now() - interval '60 minutes' AND now() + interval '1 minute'
    AND (TG_OP='INSERT' OR old.stock_status IS DISTINCT FROM new.stock_status
         OR (old.price IS NOT NULL AND new.price IS NOT NULL AND new.price < old.price)
         OR old.verified_at IS NULL) THEN
  INSERT INTO public.cny_notifications(user_id,offer_id,title,body)
  SELECT w.user_id,new.id,'Restock reported',
         p.name || ' reported in stock at ' || s.name ||
         CASE WHEN new.price IS NOT NULL THEN ' ($' || new.price::text || ')' ELSE '' END ||
         '. Confirm availability with the retailer before traveling.'
  FROM public.cny_watches w
  JOIN public.cny_profiles pr ON pr.id=w.user_id AND pr.status='approved'
  JOIN public.cny_products p ON p.slug=w.product_slug
  JOIN public.cny_stores s ON s.id=new.store_id
  WHERE w.product_slug=new.product_slug
    AND (w.max_price IS NULL OR (new.price IS NOT NULL AND new.price<=w.max_price))
    AND (cardinality(w.towns)=0 OR s.town=ANY(w.towns));
 END IF;
 RETURN new;
END;
$$;
DROP TRIGGER IF EXISTS cny_offer_notify ON public.cny_offers;
CREATE TRIGGER cny_offer_notify AFTER INSERT OR UPDATE OF stock_status, price, verified_at ON public.cny_offers FOR EACH ROW EXECUTE FUNCTION cny_private.offer_notify();

ALTER TABLE public.cny_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cny_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cny_stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cny_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cny_watches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cny_notifications ENABLE ROW LEVEL SECURITY;

-- Explicit narrow Data API grants. Never give anon access to member data.
REVOKE ALL ON public.cny_profiles,public.cny_products,public.cny_stores,public.cny_offers,public.cny_watches,public.cny_notifications FROM anon,authenticated;
GRANT SELECT ON public.cny_profiles TO authenticated;
GRANT UPDATE(status) ON public.cny_profiles TO authenticated;
GRANT SELECT ON public.cny_products,public.cny_stores,public.cny_offers,public.cny_watches,public.cny_notifications TO authenticated;
GRANT INSERT,UPDATE,DELETE ON public.cny_products,public.cny_stores,public.cny_offers TO authenticated;
GRANT INSERT,UPDATE,DELETE ON public.cny_watches TO authenticated;
GRANT UPDATE(read_at) ON public.cny_notifications TO authenticated;

CREATE POLICY cny_profile_read ON public.cny_profiles FOR SELECT TO authenticated
 USING (id=(SELECT auth.uid()) OR (SELECT cny_private.is_admin()));
CREATE POLICY cny_profile_approval ON public.cny_profiles FOR UPDATE TO authenticated
 USING ((SELECT cny_private.is_admin()) AND role='member')
 WITH CHECK ((SELECT cny_private.is_admin()) AND role='member');
CREATE POLICY cny_product_read ON public.cny_products FOR SELECT TO authenticated USING ((SELECT cny_private.is_approved()));
CREATE POLICY cny_product_admin_insert ON public.cny_products FOR INSERT TO authenticated WITH CHECK ((SELECT cny_private.is_admin()));
CREATE POLICY cny_product_admin_update ON public.cny_products FOR UPDATE TO authenticated USING ((SELECT cny_private.is_admin())) WITH CHECK ((SELECT cny_private.is_admin()));
CREATE POLICY cny_product_admin_delete ON public.cny_products FOR DELETE TO authenticated USING ((SELECT cny_private.is_admin()));
CREATE POLICY cny_store_read ON public.cny_stores FOR SELECT TO authenticated USING ((SELECT cny_private.is_approved()));
CREATE POLICY cny_store_admin_insert ON public.cny_stores FOR INSERT TO authenticated WITH CHECK ((SELECT cny_private.is_admin()));
CREATE POLICY cny_store_admin_update ON public.cny_stores FOR UPDATE TO authenticated USING ((SELECT cny_private.is_admin())) WITH CHECK ((SELECT cny_private.is_admin()));
CREATE POLICY cny_store_admin_delete ON public.cny_stores FOR DELETE TO authenticated USING ((SELECT cny_private.is_admin()));
CREATE POLICY cny_offer_read ON public.cny_offers FOR SELECT TO authenticated USING ((SELECT cny_private.is_approved()));
CREATE POLICY cny_offer_admin_insert ON public.cny_offers FOR INSERT TO authenticated WITH CHECK ((SELECT cny_private.is_admin()));
CREATE POLICY cny_offer_admin_update ON public.cny_offers FOR UPDATE TO authenticated USING ((SELECT cny_private.is_admin())) WITH CHECK ((SELECT cny_private.is_admin()));
CREATE POLICY cny_offer_admin_delete ON public.cny_offers FOR DELETE TO authenticated USING ((SELECT cny_private.is_admin()));
CREATE POLICY cny_watch_read ON public.cny_watches FOR SELECT TO authenticated USING (user_id=(SELECT auth.uid()) AND (SELECT cny_private.is_approved()));
CREATE POLICY cny_watch_insert ON public.cny_watches FOR INSERT TO authenticated WITH CHECK (user_id=(SELECT auth.uid()) AND (SELECT cny_private.is_approved()));
CREATE POLICY cny_watch_update ON public.cny_watches FOR UPDATE TO authenticated USING (user_id=(SELECT auth.uid()) AND (SELECT cny_private.is_approved())) WITH CHECK (user_id=(SELECT auth.uid()) AND (SELECT cny_private.is_approved()));
CREATE POLICY cny_watch_delete ON public.cny_watches FOR DELETE TO authenticated USING (user_id=(SELECT auth.uid()) AND (SELECT cny_private.is_approved()));
CREATE POLICY cny_notification_read ON public.cny_notifications FOR SELECT TO authenticated USING (user_id=(SELECT auth.uid()) AND (SELECT cny_private.is_approved()));
CREATE POLICY cny_notification_mark_read ON public.cny_notifications FOR UPDATE TO authenticated USING (user_id=(SELECT auth.uid()) AND (SELECT cny_private.is_approved())) WITH CHECK (user_id=(SELECT auth.uid()) AND (SELECT cny_private.is_approved()));

-- Seed online retailers only; do not invent local store addresses or inventory.
INSERT INTO public.cny_stores(retailer,name,town,website,online) VALUES
 ('Pokémon Center','Pokémon Center Online','Online','https://www.pokemoncenter.com/category/tcg-cards',true),
 ('Target','Target Online','Online','https://www.target.com',true),
 ('Best Buy','Best Buy Online','Online','https://www.bestbuy.com',true),
 ('GameStop','GameStop Online','Online','https://www.gamestop.com',true),
 ('Walmart','Walmart Online','Online','https://www.walmart.com',true)
ON CONFLICT DO NOTHING;
