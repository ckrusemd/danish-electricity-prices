# Notebook companions

[EAST.ipynb](../EAST.ipynb) selects DK2; [WEST.ipynb](../WEST.ipynb) selects DK1.
Each contains ten meaningful cells and differs only in its zone and region.
Both source `R/project.R` and `R/plots.R`, load one snapshot, and display the
same daily chart, hourly and quarter-hour tables, period averages, cheapest
upcoming and six-month historical windows, and 30-completed-day profile.
The published Quarto site remains the publication; these are exploratory
companions using the same calculations.

## Setup and Run All

Use R 4.6.1 and restore the repository's locked packages with `renv::restore()`.
Open Jupyter from the repository root so shared source paths resolve. Select
the standard **R** kernel (`ir`), then **Restart Kernel and Run All**. No
packages or kernels are installed by notebook cells or automated checks.
Quarto 1.10.19 is the publication runtime; checking these notebooks does not
require Quarto or Jupyter.

If you want interactive Jupyter execution and have no R kernel, install Jupyter
and IRkernel manually in your preferred environment. With IRkernel available
to R and Jupyter available on `PATH`, optionally register the standard kernel:

```r
IRkernel::installspec(user = TRUE, name = "ir", displayname = "R")
```

Kernel installation is optional and separate from package restoration. It does
not require changing `renv.lock` or any notebook metadata. Ensure the kernel
can see the restored project library or an explicitly configured `R_LIBS_USER`.

## Offline data or a prepared snapshot

For a complete offline Run All, set the fixture flag before launching Jupyter:

```bash
ELECTRICITY_FIXTURE=true jupyter lab
```

To reuse the exact snapshot that another consumer or the site uses, first
prepare one and then pass its path to the notebook kernel:

```bash
Rscript scripts/prepare-data.R --fixture --without-weather --output /tmp/electricity-notebooks.rds
ELECTRICITY_DATA_FILE=/tmp/electricity-notebooks.rds jupyter lab
```

`load_or_prepare_analysis(include_weather = FALSE)` reads and validates
`ELECTRICITY_DATA_FILE` when set. Otherwise it prepares one shared snapshot,
using fixture data when `ELECTRICITY_FIXTURE=true`; live preparation can
contact the public price provider. Weather is not requested by these
notebooks. A previously prepared snapshot may already contain weather.
Neither notebook sends notifications or reads notification credentials.
The provenance cell displays generation time, local analysis date, provider,
scenario, and price/weather coverage so fixture and incomplete data are visible.

## What the prices mean

Wholesale `SpotPriceDKK` is in DKK/kWh, before VAT and consumer charges.
Period averages, cheapest windows and historical profile quantiles also use
wholesale prices. A window's `average` is DKK/kWh; `total` is the sum of its
hourly wholesale prices, equivalent to the spot cost of constant 1 kW
consumption over the window. Window ends are exclusive. Unavailable windows
are displayed explicitly rather than treated as zero-price opportunities.

The hourly `SpotPriceDKK_Total` is a separate estimated consumer price in
DKK/kWh, including the shared scenario's variable components and VAT.
Component columns retain their documented units; see
[price components](../PRICE_COMPONENTS.md). The Radius/Andel scenario is an
illustration, including when applied to DK1, and is not a universal regional
tariff. Fixed subscriptions are separate from the variable price used for
consumption timing.

UTC instants determine joins, ordering, contiguous windows and aggregation.
Copenhagen time is used for dates, display and the historical clock-time
profile. A daylight saving day can have 23 or 25 hours; repeated clock times
remain distinct through their UTC columns. The median and Q25–Q75 ribbon use
the 30 completed days before the snapshot's day, limited by reported coverage,
and describe historical variation rather than a forecast. The six-month
cheapest historical window is retained independently of that profile.

## Automated validation

Run from the repository root with the locked R packages available:

```bash
Rscript --vanilla scripts/check-notebooks.R
Rscript --vanilla tests/notebooks/test-checker.R
Rscript --vanilla tests/notebooks/test-offline-guards.R
```

For a temporary compatible library, prefix the commands with
`R_LIBS_USER=/path/to/library`. The checker uses jsonlite to extract the code,
checks notebook structure and portable metadata, rejects stale outputs,
counts, execution timestamps, empty/invalid cells and embedded fetch or price
calculation calls, and parses every R cell. A quick structural check is:

```bash
Rscript --vanilla scripts/check-notebooks.R --parse-only
```

The full check executes both notebooks in fresh `Rscript --vanilla` processes
in three modes: fixture preparation, prepared snapshot reuse on the autumn
clock-change day (25 hours / 100 quarters), and empty-result presentation.
The last mode completes Run All on a valid snapshot, then exercises the window
and profile cells with an isolated empty summary copy; the saved snapshot
remains valid and untouched.
Prepared snapshot checks disable fixture preparation to verify the file takes
precedence. HTTP, socket and external command entry points are guarded in
these disposable processes; accidental network or sender calls fail the check.
Plots are rendered to a temporary PDF device and never embedded in the source
notebooks. No notification is sent, and no kernel installation is needed.

Before saving a notebook change, clear every output and execution count, and
remove execution timestamps. The checker enforces that both notebooks stay
equivalent apart from their zone and region.
