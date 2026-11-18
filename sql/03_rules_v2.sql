-- v2: rules changed by cause from the v1 miss analysis
-- rounding -> C$0.02 tolerance instead of exact amount
-- splits -> real split rule, the sum has to match
-- duplicates -> row_number() check before matching
-- every exception gets a type
drop table if exists recon_v2;
create table recon_v2 (
    ledger         char(1),
    payment_id     varchar(10),
    status         varchar(10),
    exception_type varchar(20),
    match_id       varchar(10),
    rule           varchar(12)
);

-- 1. duplicates. first posting stays in the pool, later copies get flagged
create temp table pool_a as
select x.*, row_number() over (partition by amount, counterparty, reference order by post_date, payment_id) dn
from ledger_a x;
create temp table pool_b as
select x.*, row_number() over (partition by amount, counterparty, reference order by post_date, payment_id) dn
from ledger_b x;

insert into recon_v2 select 'A', payment_id, 'EXCEPTION', 'duplicate', null, 'dup' from pool_a where dn > 1;
insert into recon_v2 select 'B', payment_id, 'EXCEPTION', 'duplicate', null, 'dup' from pool_b where dn > 1;
delete from pool_a where dn > 1;
delete from pool_b where dn > 1;
create index on pool_a (reference);
create index on pool_b (reference);

-- 2. one to one with +-3 days and C$0.02
create temp table m1 as
select * from (
    select a.payment_id a_id, b.payment_id b_id,
           row_number() over (partition by a.payment_id order by abs(a.post_date - b.post_date), abs(a.amount - b.amount), b.payment_id) ra,
           row_number() over (partition by b.payment_id order by abs(a.post_date - b.post_date), abs(a.amount - b.amount), a.payment_id) rb
    from pool_a a
    join pool_b b on a.reference = b.reference and a.counterparty = b.counterparty and a.currency = b.currency
     and abs(a.amount - b.amount) <= 0.02
     and abs(a.post_date - b.post_date) <= 3
) c where ra = 1 and rb = 1;

insert into recon_v2 select 'A', a_id, 'MATCHED', null, b_id, 'window' from m1;
insert into recon_v2 select 'B', b_id, 'MATCHED', null, a_id, 'window' from m1;
delete from pool_a where payment_id in (select a_id from m1);
delete from pool_b where payment_id in (select b_id from m1);

-- 3. split payments: 2 or 3 bank lines, same counterparty + reference, within 3 days, sum = one erp payment
create temp table m2 as
select distinct on (g.ids) g.ids, b.payment_id b_id
from (
    select counterparty, reference, currency, sum(amount) total, min(post_date) d1, max(post_date) d2,
           array_agg(payment_id order by payment_id) ids
    from pool_a
    group by counterparty, reference, currency
    having count(*) between 2 and 3 and max(post_date) - min(post_date) <= 3
) g
join pool_b b on b.reference = g.reference and b.counterparty = g.counterparty and b.currency = g.currency
 and abs(b.amount - g.total) <= 0.02
 and g.d2 - b.post_date <= 3 and b.post_date - g.d1 <= 3
order by g.ids, b.payment_id;

insert into recon_v2 select 'A', unnest(ids), 'MATCHED', null, b_id, 'split' from m2;
insert into recon_v2 select 'B', b_id, 'MATCHED', null, ids[1], 'split' from m2;
delete from pool_a where payment_id in (select unnest(ids) from m2);
delete from pool_b where payment_id in (select b_id from m2);

-- 4. whats left is an exception, try to pair it so we know what kind
create temp table pairs (a_id varchar(10), b_id varchar(10), kind varchar(20));

insert into pairs
select a_id, b_id, 'amount_mismatch' from (
    select a.payment_id a_id, b.payment_id b_id,
           row_number() over (partition by a.payment_id order by abs(a.amount - b.amount), b.payment_id) ra,
           row_number() over (partition by b.payment_id order by abs(a.amount - b.amount), a.payment_id) rb
    from pool_a a join pool_b b on a.reference = b.reference and a.counterparty = b.counterparty
     and a.currency = b.currency
     and abs(a.amount - b.amount) > 0.02 and abs(a.post_date - b.post_date) <= 3
) c where ra = 1 and rb = 1;

insert into pairs
select a_id, b_id, 'wrong_cpty_ref' from (
    select a.payment_id a_id, b.payment_id b_id,
           row_number() over (partition by a.payment_id order by abs(a.post_date - b.post_date), b.payment_id) ra,
           row_number() over (partition by b.payment_id order by abs(a.post_date - b.post_date), a.payment_id) rb
    from pool_a a join pool_b b
      on abs(a.amount - b.amount) <= 0.02 and abs(a.post_date - b.post_date) <= 3
     and ((a.reference = b.reference and a.counterparty <> b.counterparty)
       or (a.counterparty = b.counterparty and a.reference <> b.reference))
    where a.payment_id not in (select a_id from pairs) and b.payment_id not in (select b_id from pairs)
) c where ra = 1 and rb = 1;

insert into recon_v2 select 'A', a_id, 'EXCEPTION', kind, b_id, 'pair' from pairs;
insert into recon_v2 select 'B', b_id, 'EXCEPTION', kind, a_id, 'pair' from pairs;

insert into recon_v2
select 'A', payment_id, 'EXCEPTION', 'missing_in_b', null, 'leftover' from pool_a
where payment_id not in (select a_id from pairs);
insert into recon_v2
select 'B', payment_id, 'EXCEPTION', 'missing_in_a', null, 'leftover' from pool_b
where payment_id not in (select b_id from pairs);

create index on recon_v2 (ledger, payment_id);

select ledger, status, exception_type, count(*) from recon_v2 group by 1, 2, 3 order by 1, 2, 3;
