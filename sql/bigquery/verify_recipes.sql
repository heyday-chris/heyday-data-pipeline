-- ============================================================
-- Verification queries — run after each sync to confirm data
-- ============================================================


-- Row counts and date range
SELECT
  COUNT(*)                  AS total_rows,
  COUNT(DISTINCT unique_id) AS distinct_recipes,
  MIN(last_modified)        AS oldest_recipe,
  MAX(last_modified)        AS newest_recipe,
  MAX(_extracted_at)        AS last_sync
FROM `your_project.heyday_raw.flavorstudio_recipes_raw`;


-- Spot-check ingredient rows for a specific recipe
SELECT
  unique_id,
  recipe_name,
  recipe_code,
  entered_batch_size,
  batch_unit,
  JSON_VALUE(row, '$.process_step')  AS process_step,
  JSON_VALUE(row, '$.ingredient')    AS ingredient,
  JSON_VALUE(row, '$.quantity')      AS quantity,
  JSON_VALUE(row, '$.unit')          AS unit
FROM `your_project.heyday_raw.flavorstudio_recipes_raw`,
UNNEST(JSON_QUERY_ARRAY(recipeversionrows_json)) AS row
WHERE recipe_name LIKE '%Coconut Corn Chowder%'
ORDER BY process_step;


-- Check sync log
SELECT *
FROM `your_project.heyday_raw.flavorstudio_sync_log`
ORDER BY run_started_at DESC
LIMIT 10;