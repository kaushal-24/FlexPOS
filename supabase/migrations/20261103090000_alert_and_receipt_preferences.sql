-- Persist receipt output and notification preferences per business.
begin;

alter table public.businesses
  add column if not exists receipt_paper_width text not null default '80'
    check (receipt_paper_width in ('58', '80')),
  add column if not exists stock_alert_email_enabled boolean not null default false,
  add column if not exists stock_alert_email_recipients text,
  add column if not exists stock_alert_last_email_at timestamptz;

alter table public.businesses
  drop constraint if exists businesses_stock_alert_email_recipients_check,
  add constraint businesses_stock_alert_email_recipients_check
    check (
      stock_alert_email_recipients is null
      or char_length(btrim(stock_alert_email_recipients)) between 3 and 2000
    );

comment on column public.businesses.receipt_paper_width is
  'Default thermal receipt width in millimetres: 58 or 80.';
comment on column public.businesses.stock_alert_email_recipients is
  'Comma-separated notification recipients. Delivery is performed by the configured server-side email provider.';

commit;
