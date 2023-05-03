-- This query finds the total number of pallets that can be strapped with an Ergostrap annually (automatic pallet strapper)
WITH CTE_non_plt_non_rl_picks AS (
  -- PV product does not come in cases so case picks of PV is excluded
  -- Values are cast away from integer to avoid the need to recast in later calculations
  SELECT 
    ship_date, 
    order_number, 
    CAST(weight_per_line AS NUMERIC(16,8)), 
    CAST(qty_ea_on_plt AS NUMERIC(16,8)), 
    CAST(qty_ea_in_cs  AS NUMERIC(16,8)), 
    CAST(qty_bos_cs_picks AS NUMERIC(16,8)), 
    CAST(qty_pv_ea_picks AS NUMERIC(16,8)), 
    CAST(qty_bos_ea_picks AS NUMERIC(16,8)),
    -- Add columns for how much of a full pallet every applicable pick created
    -- Inner values of calulations are cast away from integer to avoid rounding in calculation
    CAST(CAST(qty_pv_ea_picks AS NUMERIC(16,8)) / qty_ea_on_plt AS NUMERIC(16,8)) AS pv_plt_of_ea,
    CAST(CAST(qty_bos_ea_picks AS NUMERIC(16,8)) / qty_ea_on_plt AS NUMERIC(16,8)) AS bos_plt_of_ea,
    CAST(CAST(qty_bos_cs_picks AS NUMERIC(16,8)) * qty_ea_in_cs / qty_ea_on_plt AS NUMERIC(16,8)) 
      AS bos_plt_of_cs
  FROM shipping_report
  -- Filter out picks with only full pallet picks because those are already strapped and rail picks because those cannot be strapped with an ergostrap
  WHERE qty_bos_cs_picks != 0 OR qty_pv_ea_picks != 0 OR qty_bos_ea_picks != 0
  -- ship_date data in table included exactly 1 year of data when this query was run
  AND ship_date > '2021-12-31'
),
-- Find the weight of bos type product in each order
-- Weights of BOS picks with both case and pallet picks may be given weights of the full pick in error, this is considered negligible
CTE_bos_plt_weight AS (
  SELECT order_number, SUM(weight_per_line) AS bos_plt_weight
  FROM CTE_non_plt_non_rl_picks
  WHERE qty_bos_ea_picks != 0 OR qty_bos_cs_picks != 0
  GROUP BY order_number
),
CTE_bos_plt_and_pv_plt_of_ea_and_cs AS (
  -- Group product of the same type and same order onto the same pallet
  SELECT order_number, SUM(pv_plt_of_ea) AS grouped_pv_plt_of_ea,
  SUM(bos_plt_of_ea) + SUM(bos_plt_of_cs) AS grouped_bos_plt_of_ea_cs
  FROM CTE_non_plt_non_rl_picks
  GROUP BY order_number
),
CTE_combined_plt_of_bos_and_pv_ea_and_cs AS (
  SELECT DISTINCT CTE_bos_plt_and_pv_plt_of_ea_and_cs.order_number, CTE_non_plt_non_rl_picks.ship_date, 
  CASE 
  -- When there is no PV and the BOS weight is less than 150lbs in the order
    WHEN CTE_bos_plt_and_pv_plt_of_ea_and_cs.grouped_pv_plt_of_ea < 0.01 
    AND CTE_bos_plt_weight.bos_plt_weight < 150 
    -- There are zero banded pallets because the BOS is sent via UPS ground which does not need banding
      THEN 0
  -- When there is PV and the BOS weight is over 75lbs in the order
    WHEN CTE_bos_plt_and_pv_plt_of_ea_and_cs.grouped_pv_plt_of_ea > 0.01 
    AND CTE_bos_plt_weight.bos_plt_weight > 75 
    -- The BOS is too heavy to put on the PV and it is separated onto its own pallet(s)
      THEN CEILING(CTE_bos_plt_and_pv_plt_of_ea_and_cs.grouped_pv_plt_of_ea) + 
      CEILING(CTE_bos_plt_and_pv_plt_of_ea_and_cs.grouped_bos_plt_of_ea_cs)
  -- In all other cases, the number of pallets is the combined pallet quantity of BOS and PV rounded up
    ELSE CEILING(CTE_bos_plt_and_pv_plt_of_ea_and_cs.grouped_pv_plt_of_ea + 
      CTE_bos_plt_and_pv_plt_of_ea_and_cs.grouped_bos_plt_of_ea_cs)
  END AS combined_plt_of_bos_and_pv_ea_and_cs
  FROM CTE_bos_plt_and_pv_plt_of_ea_and_cs
  INNER JOIN CTE_bos_plt_weight ON CTE_bos_plt_and_pv_plt_of_ea_and_cs.order_number = CTE_bos_plt_weight.order_number
  INNER JOIN CTE_non_plt_non_rl_picks ON CTE_bos_plt_and_pv_plt_of_ea_and_cs.order_number = CTE_non_plt_non_rl_picks.order_number
  ORDER BY ship_date, order_number
)
-- Sum total pallets that could have been strapped by ergostrap last year
SELECT SUM(combined_plt_of_bos_and_pv_ea_and_cs) AS total_plt_strappable_by_ergostrap
FROM CTE_combined_plt_of_bos_and_pv_ea_and_cs;