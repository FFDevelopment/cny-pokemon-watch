-- Applied to dedicated CNY Supabase project on 2026-10-22.
-- Enforces source evidence for in-stock reports, prevents duplicate locations,
-- fixes foreign key index warnings, and keeps updated_at current on each edit.
CREATE INDEX IF NOT EXISTS cny_offers_store_idx ON public.cny_offers(store_id);
CREATE INDEX IF NOT EXISTS cny_notifications_offer_idx ON public.cny_notifications(offer_id);
CREATE UNIQUE INDEX IF NOT EXISTS cny_store_name_town_ci ON public.cny_stores(lower(name),lower(town));
ALTER TABLE public.cny_offers
 ADD CONSTRAINT cny_verified_stock_requires_evidence
 CHECK (stock_status <> 'in_stock' OR
        (verified_at IS NOT NULL AND verification_method IS NOT NULL AND product_url IS NOT NULL));
CREATE OR REPLACE FUNCTION cny_private.touch_offer_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  new.updated_at := now();
  RETURN new;
END;
$$;
DROP TRIGGER IF EXISTS cny_offer_touch ON public.cny_offers;
CREATE TRIGGER cny_offer_touch BEFORE UPDATE ON public.cny_offers
FOR EACH ROW EXECUTE FUNCTION cny_private.touch_offer_updated_at();
