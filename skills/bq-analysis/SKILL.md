---
name: bq-analysis
description: Answer data questions from AfterShoot's BigQuery warehouse (project `aftershoot-analytics`) using the bq CLI — explore tables, write and run SQL, explain results in plain language, and optimize queries the user brings. Use when the user asks anything data-shaped ("how many users…", "what's the trend in…", "pull numbers for…", "query this table", "why is this query slow / expensive", "optimize this SQL") or names a warehouse table or dataset.
---

# BigQuery analysis (project `aftershoot-analytics`)

Most people using this skill do **not** write SQL. Own the query end-to-end: figure out
which table answers the question, write the SQL yourself, run it, and report the answer in
plain language. Show the SQL, but as supporting evidence — never as the deliverable, and
never ask the user to write or fix it for you.

Some users will instead paste a query and ask you to optimize it. Handle that too — the cost
rules in §5 are the same ones to optimize against.

Rules below encode measured behaviour, not folklore. Where a number appears, it was measured.

---

## 1. Use the `bq` CLI

All querying goes through the `bq` CLI. Never assume a BigQuery MCP server is present or
correctly configured.

```bash
bq query --project_id=aftershoot-analytics --use_legacy_sql=false --format=prettyjson '<SQL>'
```

Always pass `--use_legacy_sql=false`. Legacy SQL is a different dialect and will fail on
anything modern.

## 2. If `bq` isn't installed

```bash
which bq || echo "not installed"
```

If missing, install the Google Cloud SDK (which bundles `bq`):

```bash
# macOS with Homebrew
brew install --cask google-cloud-sdk

# macOS/Linux without Homebrew
curl https://sdk.cloud.google.com | bash && exec -l $SHELL
```

Then authenticate. `gcloud auth login` opens a browser, so **you cannot run it** — tell the
user to run it themselves by typing it in the session prefixed with `!`:

```bash
gcloud auth login
```

Verify with `bq ls aftershoot-analytics:` before doing anything else.

**Expired credentials look different from missing access.** This is not a permissions problem
and must not be sent to Slack — the user just needs to re-run `! gcloud auth login`:

```
There was a problem refreshing your current auth tokens: Reauthentication failed.
cannot prompt during non-interactive execution.
```

## 3. Always fully qualify table names

Write every reference as `` `aftershoot-analytics.<dataset>.<table>` `` and pass
`--project_id=aftershoot-analytics`.

Do **not** rely on the user's `gcloud config` default — it is commonly set to a different
project (`aftershoot-co` is typical). A bare `dataset.table` will silently resolve against the
wrong project. Note that query _jobs_ still bill to their config default; that's fine and
expected, it does not change which data is read.

## 4. Permission denied → `#platform-request`

```
Access Denied: Project aftershoot-analytics: User does not have bigquery.jobs.create permission
Access Denied: Table aftershoot-analytics:<dataset>.<table>: User does not have permission to query table
```

Stop and tell the user:

> You don't have BigQuery access for this. Raise a ticket in the **#platform-request** Slack
> channel asking for BigQuery read access to `aftershoot-analytics` (mention the specific
> dataset or table), and retry once it's granted.

Do not try other projects, other credentials, or a different auth path to get around it.
Do not guess at or fabricate the numbers the query would have returned — say it didn't run and why.

## 5. Cost discipline

### 5a. Dry-run every query before running it

```bash
bq query --project_id=aftershoot-analytics --dry_run --use_legacy_sql=false '<SQL>'
```

The limit for self-serve queries is **100 GB** (100,000,000,000 bytes).

### 5b. The estimator is badly wrong about JSON — discriminate before you gate

`--dry_run` reports `UPPER_BOUND` and **cannot see JSON subfield pruning**. It quotes the size
of the entire JSON column even when the query reads one key. Measured on
`posthog_events__daily__facts`, 30 days:

|                                         | estimate    | actually billed |
| --------------------------------------- | ----------- | --------------- |
| `json_value(properties, '$.Cull Type')` | 1,057.8 GiB | **0.5 GiB**     |

A 2,100× over-estimate. So when the dry run exceeds 100 GB, check _how_ the query touches JSON
before doing anything:

- **Every JSON reference is by path** — `json_value(...)`, `json_query(...)`, or a hoisted view
  column (`cull_type`, `software`, `profile_type`, `discord_build`, …) — **and** there is no
  bare `properties`, no `to_json_string(properties)`, and no `SELECT *`
  → the estimate is inflated. **Ignore the gate and run it.** Mention the estimate is unreliable.
- **Anything materializes the whole JSON** (`SELECT properties`, `to_json_string(properties)`,
  `SELECT *`) → the estimate is accurate. Apply the gate.

Per-day cost on that table, measured: path access ≈ **0.02 GiB/day**, whole-JSON ≈ **37.6 GiB/day**.

### 5c. Over 100 GB and not the JSON case → refuse

Do not run it, and do not run it "just this once". Tell the user:

> This query would scan about **X GB**, over the 100 GB self-serve limit, so I haven't run it.
> We can bring it under the limit by [narrowing the date range / filtering on `event` /
> > selecting fewer columns]. If you need this regularly, ask **#data-requests** to materialize
> it into a table — that makes it cheap to query repeatedly.

Then offer the narrowed version and dry-run that instead.

### 5d. Never pass `--maximum_bytes_billed`

It is enforced against the **estimate**, not the bill, so it inherits the blind spot in §5b and
hard-fails legitimate queries. Measured: the 30-day `json_value` query above (0.5 GiB actual)
is rejected by a 100 GB cap.

### 5e. Free operations — prefer these for exploration

Never spend a query on something these answer:

```bash
bq head -n 20 --selected_fields=col_a,col_b aftershoot-analytics:<dataset>.<table>   # free
bq show --schema --format=prettyjson aftershoot-analytics:<dataset>.<table>          # free
```

`bq head` does not work on views (`Cannot list a table of type VIEW`) and ignores
`require_partition_filter`. It reads in storage order, so rows are **not** recent — fine for
"what do the values look like", useless for "what happened yesterday".

### 5f. Reporting what a query actually cost

The only ground truth. Costs ~0.02 GiB itself:

```sql
SELECT
  ROUND(total_bytes_billed / POW(2,30), 2) AS billed_gib,
  ROUND(total_bytes_billed / POW(2,40) * 6.25, 4) AS est_usd,
  SUBSTR(REPLACE(query, '\n', ' '), 1, 80) AS q
FROM `aftershoot-analytics.region-us-central1.INFORMATION_SCHEMA.JOBS_BY_USER`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 MINUTE)
  AND statement_type = 'SELECT'
ORDER BY creation_time DESC
LIMIT 10
```

## 6. PostHog app events

### 6a. One table only

```
`aftershoot-analytics.aftershoot_gold_layer.posthog_events__daily__facts`
```

This is **the** table for app events. Never use the raw sources in the `events` dataset for
ad-hoc analysis — `posthog_wap_events`, `posthog_events`, `aftershoot_gallery_event`. (dbt
models _do_ read them to build this table; that's the pipeline's job, not yours.)

Two related tables that **are** allowed:

- `aftershoot_gold_layer.posthog_website_events__daily__facts` — marketing-site events, a
  genuinely different dataset from app events.
- `events.posthog_persons` / `events.posthog_wap_persons` — user attributes not carried on
  events (GPU / inference backend, country).

### 6b. A date filter is mandatory

The underlying physical table sets `require_partition_filter`. Without a filter on
`event_timestamp` the query does not run slow — it **errors**:

```
Cannot query over table '...posthog_events__internal__daily__facts' without a filter over
column(s) 'event_timestamp' that can be used for partition elimination
```

### 6c. Filter on `event` — this is the single highest-leverage rule

Clustered on `event, user_id, project_id`, in that order. One day, measured:

| filter                 | scanned      |
| ---------------------- | ------------ |
| date only              | 37.62 GiB    |
| date + `event = '...'` | **0.04 GiB** |
| date + event + user_id | 0.04 GiB     |

854× from `event` alone. `user_id` adds little once `event` is pinned — useful for narrowing to
a specific user, not as a cost lever. Always ask what event(s) the question is about, and if the
user doesn't know, find it from the catalog in §6e rather than scanning everything.

### 6d. Never materialize the whole JSON

`properties` is a native JSON column, ~37.6 GiB per day of history.

```sql
-- NEVER: all three read the entire column
SELECT properties ...
SELECT to_json_string(properties) ...
SELECT * ...

-- ALWAYS: read by path, ~0.02 GiB/day
SELECT json_value(properties, '$.Cull Type') ...
```

The view's hoisted columns (`cull_type`, `software`, `profile_type`, `discord_build`,
`number_of_catalogs`, `createdFromTerminal`) are `json_value` in disguise and are equally cheap —
prefer them when they cover what you need.

If the user genuinely wants to _see_ the properties, don't dump the JSON: pull the specific keys
they care about with `json_value`, or show the catalog rows from §6e.

### 6e. Finding out what's inside `properties`

Don't scan `properties` to discover keys. Use the catalog — 888 KB to full-scan, effectively free:

```
`aftershoot-analytics.aftershoot_gold_layer.posthog_event_property_keys__daily__facts`
```

| column                     | meaning                                              |
| -------------------------- | ---------------------------------------------------- |
| `event`                    | PostHog event name                                   |
| `property_key`             | key inside `properties`, nested keys dot-joined      |
| `json_path`                | ready to paste into `json_value(properties, <this>)` |
| `first_seen` / `last_seen` | stale `last_seen` ⇒ the key is no longer sent        |
| `rows_with_key_last_day`   | how common the key currently is — rank by this       |

```sql
SELECT property_key, json_path, rows_with_key_last_day
FROM `aftershoot-analytics.aftershoot_gold_layer.posthog_event_property_keys__daily__facts`
WHERE event = 'Culling Completed'
ORDER BY rows_with_key_last_day DESC
```

`json_path` already includes the `$.` prefix. Paste it as-is — **do not** add quotes around it,
that breaks nested paths.

**The catalog excludes PostHog's own `$`-prefixed keys** (`$browser`, `$device_id`, `$geoip_*`,
`$session_id`, `$feature/<flag>`, …). They exist in `properties`, they're just not listed. So a
question about browser or geo is answerable — the key simply won't be in the catalog. Reach them
by path, and note the segment **must be quoted**:

```sql
json_value(properties, '$."$browser"')   -- works
json_value(properties, '$.$browser')     -- Invalid JSON Path
```

## 7. Cull AI scores

### 7a. Use the table-valued function, not the view

```sql
SELECT *
FROM `aftershoot-analytics.aftershoot_gold_layer.userXalbumXgenreXimage__cull_ai_score__daily__facts`(
       'some_user_id', NULL, 30)
```

Args are positional: `(p_user_id STRING, p_project_id STRING, p_lookback_days INT64)`.

- **`user_id` is required.** The function body is `WHERE user_id = p_user_id`, so passing `NULL`
  returns **zero rows with no error**. If a result set is unexpectedly empty, check this first.
- `project_id` — pass `NULL` for all projects belonging to that user.
- `lookback_days` — pass `NULL` for the 7-day default. Filters `updated_at`.

Returns `user_id, project_id, genre, image, updated_at`, one row per image, already reduced to
the latest scoring run per (user_id, project_id).

**Do not query the plain view of the same name.** It runs `ROW_NUMBER()` over the entire
underlying table with no filter, so it always full-scans. The TVF exists precisely to push the
partition and cluster filters down.

Ignore `..._cull_ai_score__daily__facts__tvfcheck` — a stray duplicate, not the supported entry point.

### 7b. Cross-user questions

The TVF can't answer "across all users" since `user_id` is required. Go to the physical table:

```
`aftershoot-analytics.aftershoot_gold_layer__physical.userXalbum__ai_scores__daily__facts`
```

Partitioned on `updated_at`, clustered on `user_id, project_id, genre`. Two requirements:

1. **Always filter `updated_at`** — it's a large table and this is the only partition lever.
2. **You must dedupe yourself.** The latest-per-album logic lives in the view and TVF, not the
   table, so the raw table carries multiple scoring runs per album:

```sql
WITH latest AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id, project_id ORDER BY updated_at DESC) AS rn
  FROM `aftershoot-analytics.aftershoot_gold_layer__physical.userXalbum__ai_scores__daily__facts`
  WHERE updated_at >= TIMESTAMP(CURRENT_DATE - 7)
)
SELECT ... FROM latest, UNNEST(image) AS image WHERE rn = 1
```

Skipping the dedupe silently double-counts. The normal §5 gate applies.

## 8. Read-only

This skill is for analysis. Do not run `CREATE`, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, or
`DROP` against the warehouse. Anything that needs a new table, column, or model goes to the dbt
repo (`aftershoot-dbt-service`) as a PR, or to **#data-requests**.
