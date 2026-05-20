# Heyday Data Pipeline

FlavorStudio → BigQuery → dbt → Cin7

## Architecture
FlavorStudio API → n8n → BigQuery raw layer → dbt transforms → Cin7 BOM sync

## Repository Structure
- `/docs` — integration context, API notes, architecture decisions
- `/sql/bigquery` — table DDL and verification queries
- `/workflows` — n8n workflow JSON exports
- `/dbt` — dbt project (Phase 2)

## Setup
1. Copy `.env.example` to `.env` and fill in credentials
2. Run SQL in `/sql/bigquery/create_tables.sql` to initialize BigQuery tables
3. Import workflow JSON from `/workflows` into n8n

## Status
- [ ] Phase 1: FlavorStudio → BigQuery raw ingestion
- [ ] Phase 2: dbt transformation layer
- [ ] Phase 3: Cin7 BOM sync + approval workflow