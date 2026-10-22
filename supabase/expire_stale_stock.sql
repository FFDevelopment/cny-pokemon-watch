-- Safety net only: does not check external retailer inventory.
-- Supabase Cron marks reports of in-stock older than 60 minutes as unknown.
-- This prevents an outdated report from masquerading as currently verified stock.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

CREATE OR REPLACE FUNCTION cny_private.expire_stale_offers()
RETURNS integer
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE affected integer;
BEGIN
  UPDATE public.cny_offers
  SET stock_status = 'unknown'
  WHERE stock_status = 'in_stock'
    AND (verified_at IS NULL OR verified_at < now() - interval '60 minutes');
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$$;

-- Runs as the owner (postgres) from Cron; app clients may not invoke it.
REVOKE ALL ON FUNCTION cny_private.expire_stale_offers() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'cny-expire-stale-stock',
  '*/10 * * * *',
  'SELECT cny_private.expire_stale_offers();'
);
