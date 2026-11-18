-- views power bi reads (import or directquery)
drop view if exists v_recon cascade;
drop table if exists fx_rate;

-- usd->cad rate is an assumption, set it to the boc rate for your period
create table fx_rate (currency char(3) primary key, to_cad numeric(8,4));
insert into fx_rate values ('CAD', 1.0), ('USD', 1.37);

create view v_recon as
select r.ledger, r.payment_id, r.status, r.exception_type, r.rule, r.match_id,
       x.post_date, date_trunc('week', x.post_date)::date week_start,
       x.amount, x.currency, round(x.amount * f.to_cad, 2) amount_cad,
       x.counterparty, x.reference, x.source_system,
       case when r.status = 'EXCEPTION' then 'Open' end exception_status
from recon_v2 r
join (select 'A' ledger, * from ledger_a union all select 'B', * from ledger_b) x
  on x.ledger = r.ledger and x.payment_id = r.payment_id
join fx_rate f on f.currency = x.currency;
