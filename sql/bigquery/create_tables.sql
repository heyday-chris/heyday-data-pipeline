-- ============================================================
-- FlavorStudio Raw Layer — BigQuery Table Definitions
-- Project: Heyday Data Pipeline
-- Last updated: 2026-05-20
-- ============================================================


-- ------------------------------------------------------------
-- Table 1: Recipe versions with ingredient rows as JSON
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `heyday-bigquery-dev.heyday_raw.flavorstudio_recipes_raw` (
  _extracted_at           TIMESTAMP NOT NULL,
  _extraction_run_id      STRING    NOT NULL,
  _page                   INT64,
  unique_id               STRING,
  recipe_name             STRING,
  recipe_code             STRING,
  recipe_in_production    STRING,
  recipe_archived         STRING,
  type                    STRING,
  created                 STRING,
  last_modified           STRING,
  recipeversion_version   STRING,
  recipeversion_name      STRING,
  recipeversion_notes     STRING,
  entered_batch_size      STRING,
  batch_unit              STRING,
  recipeversionrows_json  STRING,
  tags_json               STRING
);


-- ------------------------------------------------------------
-- Table 2: Ingredient master
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `heyday-bigquery-dev.heyday_raw.flavorstudio_ingredients_raw` (
  _extracted_at       TIMESTAMP NOT NULL,
  _extraction_run_id  STRING    NOT NULL,
  ingredient_id       STRING,
  ingredient_name     STRING,
  item_code           STRING,
  category            STRING,
  supplier            STRING,
  cost                STRING,
  unit                STRING,
  storage             STRING,
  enabled             STRING,
  notes               STRING,
  organic             STRING,
  non_gmo             STRING,
  kosher              STRING,
  halal               STRING,
  gf                  STRING
);


-- ------------------------------------------------------------
-- Table 3: Sync log — one row per n8n run
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `heyday-bigquery-dev.heyday_raw.flavorstudio_sync_log` (
  run_id                  STRING    NOT NULL,
  run_started_at          TIMESTAMP,
  run_completed_at        TIMESTAMP,
  trigger_type            STRING,
  recipes_fetched         INT64,
  recipe_versions_fetched INT64,
  ingredients_fetched     INT64,
  api_calls_used          INT64,
  remaining_api_calls     INT64,
  status                  STRING,
  error_message           STRING
);