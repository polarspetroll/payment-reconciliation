-- v1, deliberately simple
-- 1. exact amount + reference + counterparty, post date within 3 days, one to one
-- 2. bank lines sharing a reference on the same day = one split payment (sum not checked)
-- 3. anything left gets flagged
drop table if exists recon_v1;
create table recon_v1 (
    ledger         char(1),
    payment_id     varchar(10),
    status         varchar(10),
    exception_type varchar(20),
    match_id       varchar(10),
    rule           varchar(12)
);

create temp table m1 as
select * from (
    select a.payment_id a_id, b.payment_id b_id,
           row_number() over (partition by a.payment_id order by abs(a.post_date - b.post_date), b.payment_id) ra,
           row_number() over (partition by b.payment_id order by abs(a.post_date - b.post_date), a.payment_id) rb
    from ledger_a a
    join ledger_b b on a.reference = b.reference and a.counterparty = b.counterparty
     and a.amount = b.amount and abs(a.post_date - b.post_date) <= 3
) c where ra = 1 and rb = 1;

insert into recon_v1 select 'A', a_id, 'MATCHED', null, b_id, 'exact' from m1;
insert into recon_v1 select 'B', b_id, 'MATCHED', null, a_id, 'exact' from m1;

-- same ref + same day on the bank side, assume its a split
create temp table same_day as
select reference, post_date from ledger_a group by 1, 2 having count(*) > 1;

insert into recon_v1
select 'A', a.payment_id, 'MATCHED', null, null, 'split'
from ledger_a a join same_day s using (reference, post_date)
where a.payment_id not in (select a_id from m1)
  and exists (select 1 from ledger_b b where b.reference = a.reference);

insert into recon_v1
select 'B', b.payment_id, 'MATCHED', null, null, 'split'
from ledger_b b
where b.payment_id not in (select b_id from m1)
  and b.reference in (select reference from same_day);

insert into recon_v1
select 'A', payment_id, 'EXCEPTION', 'unmatched', null, 'leftover' from ledger_a
where payment_id not in (select payment_id from recon_v1 where ledger = 'A');
insert into recon_v1
select 'B', payment_id, 'EXCEPTION', 'unmatched', null, 'leftover' from ledger_b
where payment_id not in (select payment_id from recon_v1 where ledger = 'B');

create index on recon_v1 (ledger, payment_id);

select ledger, status, rule, count(*) from recon_v1 group by 1, 2, 3 order by 1, 2, 3;
