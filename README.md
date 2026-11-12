# Zen City: What's Really Holding Back Bike Rentals?

**A SQL case study: from one quarter of raw bike-share data (Q1 2022) to a data-driven growth plan for Q2.**

Team project by **Telem Azaria** and **Daniel Joseph** · Data Analyst with AI, Reichman University · September 2026

**My part (Telem):** data cleaning, writing the SQL script in BigQuery, building the presentation and the interactive station map.

[Interactive station map](https://tha2320-boop.github.io/zen-city-map) · [Class presentation](https://tha2320-boop.github.io/zen-city-presentation) · [Full SQL script](zen_city_analysis.sql) · [Project document (PDF)](project_document.pdf)

---

## The business question

Zen City, a bike rental company, shared its Q1 2022 data (January - March) and asked for a plan to **get more rentals in Q2 without investing in expansion first**: find overcrowded and underutilized stations, make the service more useful, and grow the user base.

We started with a question, not a chart: *what is limiting the number of rentals?* Bike shortages, idle docks, a narrow customer mix and bad timing each lead to a different action, so the data had to tell us which one applies.

## Key results

| | |
|---|---|
| **16,578** | clean trips analyzed (from 16,585 raw) |
| **10 → 79** | origin stations → destination stations |
| **77.3%** | of trips made by student members |
| **53** | rentals forecast at station 2498 on April 1st, 2022 |

## The data

Two Google BigQuery tables:

- `station_info` - one row per station (102 stations): name, status, number of docks, footprint and more.
- `rentals` - one row per trip (16,585 trips): trip_id, subscriber type, bike, start time, start and end station, duration.

## Approach

| Stage | Question | Method |
|---|---|---|
| 1. Business topic | What does success look like? | Project brief, domain research |
| 2. Exploration | Volume, ranges, nulls, anomalies? | SQL profiling queries, Excel histogram |
| 3. Hypotheses | Which questions matter for Q2? | 4 hypotheses + 1 prediction |
| 4. Cleaning | Can we trust each row? | One master CTE chain |
| 5. Analysis | What drives or blocks rentals? | SQL metrics, Excel pivots and charts |
| 6. Prediction | Rentals at station 2498 on April 1st? | Friday series + least-squares trend in SQL |

Every number was produced in SQL and then **verified independently in Excel** with pivot tables. When the two tools agreed, we trusted the number.

## Data cleaning

All cleaning lives in one reusable CTE chain, `station_crosswalk → deduplicated_rentals → cleaned_rentals`, so every analysis query starts from the same clean dataset.

- **Inconsistent IDs** - 6 station IDs in `rentals` didn't match `station_info`; resolved with a crosswalk table built with `UNNEST([STRUCT(...)])`.
- **Duplicates** - `ROW_NUMBER() OVER (PARTITION BY trip_id)` keeps one row per trip (none found, kept as a safeguard).
- **Missing values** - 1 trip with no end station removed; 20 stations with invalid dock counts flagged, not deleted.
- **Outliers** - 6 trips over 24 hours (up to 4,874 minutes) removed.
- **Standardization** - two names for the same student product merged; station status normalized with `LOWER(TRIM())`.

| Step | Trips |
|---|---|
| Raw rentals | 16,585 |
| − duplicate trip IDs | 0 |
| − trip with no end station | 1 |
| − trips over 24 hours | 6 |
| **Clean dataset** | **16,578** |

## Findings

### 1. A network that only runs one way
Every trip started at just **10 stations** but ended at **~80**. Of 78 active stations, 68 were never used as a starting point. Most origins surround the University of Texas campus: Zen City is a campus mobility engine, not a citywide commuter network.

### 2. A few stations carry the load, most docks sit idle
We designed (with an AI assistant) a metric that's fair to stations of different sizes: **Traffic per Dock = (departures + arrivals) ÷ docks**. Thresholds were validated against the real distribution: mean + 1 SD = 101.9, almost exactly the "overcrowded" cutoff of 100.

- **9** stations overcrowded (> 100) - led by 22nd ½ & Rio Grande at 343
- **6** balanced (10 - 100)
- **63** underutilized (< 10) - the median station saw only 3.1 movements per dock all quarter

Between 1 and 6 am the whole network starts only **2% of trips**, a quiet window for rebalancing.

### 3. Non-student riders are a different audience
| Segment | Share of trips | Weekend share | Median ride |
|---|---|---|---|
| Students | 77.3% | 17.7% | 5 min |
| Other members | 14.4% | 26.9% | 15 min |
| Casual / short-term | 8.3% | 44.2% | 24 min |

Student trips dropped **87%** during Spring Break, a risky dependency before summer. Casual riders ride on weekends, ride longer, and 59% of their trips start at three leisure and event stations.

### 4. Forecast: 53 rentals on April 1st
A series of all Q1 Fridays at station 2498 (excluding the Spring Break Friday), a least-squares trend of +5.01 rentals per week, and the March Friday average (48.3) projected one week ahead: **48.3 + 5.01 ≈ 53**. Compared against six simpler methods (range 34 - 65) to confirm it's plausible. *Limitations: 11 data points, no weather data.*

## Recommendations for Q2

1. **Nightly rebalancing** - return bikes from the ~80 destination stations to the top origins between 1 and 6 am.
2. **Shift idle capacity** - consider moving docks from underutilized stations instead of new construction.
3. **Convert event riders** - partner with Q2 events (Cap10K, Blues on the Green) to turn weekend riders into members, measured by pass redemptions and 30-day membership conversion.

## Tools

Google BigQuery (SQL: CTEs, window functions, `UNNEST`, `APPROX_QUANTILES`, least-squares regression) · Microsoft Excel (pivot tables, histogram, Pareto chart) · AI assistant (metric design and validation)

## Repository files

| File | What's inside |
|---|---|
| [`zen_city_analysis.sql`](zen_city_analysis.sql) | Commented SQL script: profiling, master cleaning CTE, all analysis and forecast queries |
| [`project_document.pdf`](project_document.pdf) | Full project document (10 pages) |
| [`presentation.pdf`](presentation.pdf) | Class presentation (7 slides) |
| [`cleaned_data.xlsx`](cleaned_data.xlsx) | Clean dataset (16,578 trips) |
| [`analysis_workbook.xlsx`](analysis_workbook.xlsx) | Excel verification: pivot tables, histogram, Pareto chart |
| [`rentals.xlsx`](rentals.xlsx), [`station_info.xlsx`](station_info.xlsx) | Original tables exported from BigQuery |
