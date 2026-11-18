drop table if exists ledger_a, ledger_b, truth cascade;

create table ledger_a (
    payment_id    varchar(10) primary key,
    post_date     date not null,
    amount        numeric(14,2) not null,
    currency      char(3) not null,
    counterparty  varchar(40) not null,
    reference     varchar(16) not null,
    source_system varchar(7) not null
);

create table ledger_b (like ledger_a including all);

create table truth (
    exception_id int not null,
    record_id    varchar(10) not null,
    ledger       char(1) not null,
    type         varchar(20) not null
);

-- indexes the rules lean on
create index on ledger_a (amount);
create index on ledger_a (post_date);
create index on ledger_a (reference);
create index on ledger_b (amount);
create index on ledger_b (post_date);
create index on ledger_b (reference);
create index on truth (ledger, record_id);
