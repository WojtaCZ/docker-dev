---
name: db-schema-review
description: Review relational database schemas for normalisation, indexing, naming conventions, integrity constraints, and query-performance implications. Covers MySQL/MariaDB, PostgreSQL, and SQLite.
---

Analyse the provided schema (DDL, ORM model, migration file, or prose description) and produce a structured review covering:

## 1. Normalisation
- Identify 1NF/2NF/3NF violations (repeating groups, partial dependencies, transitive dependencies).
- Suggest decomposition where appropriate; note when denormalisation is intentional and correct (e.g. reporting tables, event logs).

## 2. Primary & foreign keys
- Confirm every table has a PK. Flag composite PKs that could be replaced with a surrogate.
- Check FK constraints exist and are appropriate (ON DELETE / ON UPDATE actions).
- Flag missing FK constraints (columns named `foo_id` with no FK).

## 3. Indexes
- Suggest indexes for columns that appear in JOIN ON, WHERE, GROUP BY, or ORDER BY clauses based on the schema's apparent use case.
- Flag redundant indexes (duplicates, prefix of composite index).
- Note indexes that hurt write performance relative to their read benefit.

## 4. Data types
- Flag oversized types (VARCHAR(255) where 50 suffices) and undersized ones (TINYINT for IDs that will grow).
- Recommend ENUM vs lookup-table trade-offs.
- Flag TEXT/BLOB columns in indexed positions.

## 5. Constraints & integrity
- Missing NOT NULL where semantically required.
- Missing UNIQUE constraints.
- CHECK constraints that should exist.

## 6. Naming
- Consistent singular/plural table naming.
- Consistent column naming (snake_case vs camelCase, `id` vs `table_id`).
- Ambiguous names (`data`, `value`, `info`).

## 7. Migration safety
- Identify changes that require a lock or cause downtime on large tables.
- Suggest online-safe alternatives (pt-online-schema-change, pg_repack, `ALGORITHM=INPLACE`).

Produce a prioritised list of issues (P0 data-integrity risk → P3 cosmetic) and a corrected DDL snippet for each significant finding.
