# Danish Electricity Prices

A daily Quarto website for DK1 (West) and DK2 (East), with Pushover notifications
and a heat-pump price/temperature heat map.

[Open the publication](https://ckrusemd.github.io/danish-electricity-prices/).

## One calculation pipeline

Shared R modules prepare a validated snapshot once. Quarto pages, exploratory
notebooks and notification previews consume that snapshot instead of fetching
or calculating prices independently.

Prices retain 15-minute resolution; hourly summaries come from the same data.
Today's graph includes median and Q25–Q75 overlays for the preceding 30 completed
Copenhagen dates. All prices are in DKK/kWh. The consumer-price scenario uses
documented Andel FlexEnergi/Radius components; it does not describe every DK1
customer. Fixed subscriptions remain separate.

The heat map uses 1 °C bands and hours 07–23, with dark blue for lowest mean
price and white for highest. Modeled hourly temperatures are joined to prices
by exact UTC hour. This is decision support, not a measured COP curve.
Coverage, source and generation time are displayed.

Electricity comes from [Energi Data Service DayAheadPrices](https://api.energidataservice.dk/dataset/DayAheadPrices).
Weather comes from the [Open-Meteo Historical Forecast API](https://open-meteo.com/en/docs/historical-forecast-api),
with attribution. This personal, non-commercial project uses its free endpoint;
publication no longer needs an OpenWeather secret.

## Local development

Use R 4.6.1, Quarto 1.10.19 and the packages in `renv.lock`. Restore the
locked library explicitly, matching the container's batch execution:

```bash
export R_LIBS_USER="$PWD/.cache/r-library"
bash scripts/environment-restore.sh "$R_LIBS_USER"
```

Interactive startup never installs packages. Missing packages cause an error
instead of being downloaded during a render. Automation uses `Rscript --vanilla`.

Prepare real data and render:

```bash
Rscript --vanilla scripts/prepare-data.R --output .cache/analysis.rds
ELECTRICITY_DATA_FILE=.cache/analysis.rds quarto render
```

Render deterministic offline fixtures without credentials:

```bash
Rscript --vanilla scripts/prepare-data.R --fixture --output .cache/fixture-analysis.rds
ELECTRICITY_DATA_FILE=.cache/fixture-analysis.rds quarto render
```

Preview a notification without sending:

```bash
Rscript --vanilla scripts/send-pushover.R --dry-run --fixture
```

The explicit Quarto render list contains five pages. Jupyter notebooks are
exploratory companions excluded from publication; see
[notebook instructions](notebooks/README.md).

## Deployment and morning delivery

Pages publication and notification are independent workflows, both targeting
**05:00 Europe/Copenhagen**. Prepared free external cron jobs retry at 05:15 and
05:30; GitHub schedules provide later recovery. Early and completed invocations
exit promptly without waiting for a clock time.

See [scheduler setup](ops/README.md) and
[workflow operations](.github/workflows/README.md). Scheduler templates are
disabled until the external account and repository-scoped token are configured;
committing a template does not activate scheduling.

Notification state records an attempt before posting and saves confirmed
Pushover acceptance. A lost response remains uncertain and is not automatically
resent. Pushover acceptance confirms queuing, not that the phone displayed it.
Notification and Pages state remain independent.

Set **Settings → Pages → Source** to **GitHub Actions**. Public Pages and standard
runners keep the intended setup free. Verified container images are selected by
environment fingerprint and immutable digest. Packages are restored when the
image is built, not during every publication. A failed build preserves the last
successful site. Build metadata records source/environment identity, coverage
and timings.

## Repository map

| Area | Purpose |
|---|---|
| `*.qmd`, `_quarto.yml`, `style.css` | Publication |
| `R/` | Shared data, calculations and charts |
| `EAST.ipynb`, `WEST.ipynb` | Exploratory notebooks |
| `scripts/`, `tests/` | Preparation, preview and regression checks |
| `.github/workflows/` | CI, environment, Pages and delivery |
| `ops/` | External scheduler setup |
| `renv.lock`, `Dockerfile` | Runtime |

Historical input caches accelerate repeat runs; current prices refresh on actual
execution. Generated data, render output and previews stay out of version
control. Keep credentials in GitHub secrets or the scheduler's protected
settings, never in source or notebook outputs. See [SECURITY.md](SECURITY.md).
