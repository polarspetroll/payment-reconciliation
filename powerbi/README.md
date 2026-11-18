# Power BI dashboard

Built in Power BI Desktop (Windows) on top of the `v_recon` view.

1. Run `sql/05_powerbi_views.sql` after the v2 rules
2. Get Data > PostgreSQL database, server `localhost:5432`, database `recon`, pick Import (or DirectQuery)
3. Load `v_recon`, then paste the measures from `measures.dax` (Modeling > New measure)
4. Pages
   - **Overview**: cards for Exception Count, Exception Rate, $ At Risk, slicers for source system, currency, ledger
   - **By type**: bar chart exception_type x Exception Count, $ At Risk as tooltip
   - **By source system**: clustered bar source_system x Exception Count and Exception Rate
   - **By week**: line chart week_start x Exception Count
   - **Open exceptions**: table (payment_id, ledger, exception_type, counterparty, reference, amount_cad) filtered to Open, sorted by amount_cad desc
5. Save as `powerbi/recon_dashboard.pbix`

Note: `$ At Risk` converts USD at the rate in the `fx_rate` table (1.37 is a placeholder, update it).
