-- run with: psql -v tbl=recon_v1 -v out=results/miss_analysis_v1.csv -f sql/04_miss_analysis.sql
-- groups missed exceptions and false flags by likely cause

create temp table all_rows as
select 'A'::char(1) ledger, * from ledger_a
union all
select 'B', * from ledger_b;
create index on all_rows (ledger, payment_id);
create index on all_rows (reference);

-- bank refs posted as more than one line
create temp table multi_ref as
select reference from ledger_a group by 1 having count(*) > 1;

-- missed = every record of the exception came out MATCHED
create temp table missed as
select t.exception_id, t.ledger, t.record_id payment_id, r.rule, r.match_id
from truth t join :tbl r on r.ledger = t.ledger and r.payment_id = t.record_id
where t.exception_id not in (
    select t2.exception_id from truth t2
    join :tbl r2 on r2.ledger = t2.ledger and r2.payment_id = t2.record_id
    where r2.status <> 'MATCHED');

create temp table causes as
select 'missed exception' kind, m.exception_id, m.ledger, m.payment_id,
    case
        when m.rule = 'split' then 'split payment'
        when abs(x.amount - o.amount) > 0 then 'rounding'
        when x.post_date <> o.post_date then 'date lag'
        else 'other'
    end cause
from missed m
join all_rows x on x.ledger = m.ledger and x.payment_id = m.payment_id
left join all_rows o on o.ledger <> m.ledger and o.payment_id = m.match_id
union all
select 'false positive', null, r.ledger, r.payment_id,
    case
        when x.reference in (select reference from multi_ref) then 'split payment'
        when exists (select 1 from all_rows o where o.ledger <> x.ledger and o.reference = x.reference
                     and abs(o.amount - x.amount) between 0.01 and 0.05) then 'rounding'
        when exists (select 1 from all_rows o where o.ledger <> x.ledger and o.reference = x.reference
                     and o.amount = x.amount and abs(o.post_date - x.post_date) > 3) then 'date lag'
        else 'other'
    end
from :tbl r
join all_rows x on x.ledger = r.ledger and x.payment_id = r.payment_id
left join truth t on t.ledger = r.ledger and t.record_id = r.payment_id
where r.status <> 'MATCHED' and t.record_id is null;

create temp table summary as
select kind, cause, count(*) records, count(distinct exception_id) exceptions,
       round(100.0 * count(*) / sum(count(*)) over (partition by kind), 1) pct_of_kind
from causes
group by kind, cause;

\echo miss analysis for :tbl
select * from summary order by kind desc, records desc;

\pset format csv
\o :out
select * from summary order by kind desc, records desc;
\o
