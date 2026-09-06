# Danish Electricity Prices

Automated analysis and forecasting of Danish electricity spot prices for the East (DK2) and West (DK1) price areas.

Built as a [bookdown](https://bookdown.org/) site, deployed via GitHub Actions and published to GitHub Pages.

## Features

- Fetches current day-ahead prices from the [Energi Data Service API](https://www.energidataservice.dk/)
- Calculates total consumer price including transport tariffs and electricity tax (*elafgift*)
- Finds the cheapest upcoming hours and rolling time windows (2–3 hours)
- Builds a decision-tree model (rpart) to predict price levels by day-of-week and hour

## Project Structure

```
├── index.Rmd            # Bookdown index / landing page
├── EAST.Rmd             # Analysis for East Denmark (DK2)
├── WEST.Rmd             # Analysis for West Denmark (DK1)
├── _bookdown.yml        # Bookdown configuration
├── EAST.ipynb            # 15-minute Jupyter analysis for DK2
├── WEST.ipynb            # Adapted 15-minute Jupyter analysis for DK1
├── renv.lock            # R package lockfile (renv)
└── .github/workflows/   # CI/CD — build & deploy to GitHub Pages
```

## GitHub Actions and deployment

The repository uses two workflows:

- **Build and deploy electricity prices** restores the locked R environment,
  renders the site, and publishes it to GitHub Pages. It runs daily at 16:17
  UTC, on relevant source changes to `master`, or manually through **Actions →
  Run workflow**.
- **Security checks** scans the working tree and full Git history for common
  credentials and validates the repository configuration on pushes and pull
  requests.

Set **Settings → Pages → Source** to **GitHub Actions**. The deployment uses
standard runners and public GitHub Pages, so it requires no paid infrastructure
or application secrets. The R package cache is keyed from `renv.lock`; changing
that file automatically creates a fresh dependency cache.

If a scheduled build fails, open the failed run under **Actions**, inspect the
first error, correct it, and use **Run workflow**. A successful build must
complete before Pages is updated.

## Setup

1. **Install R** (≥ 4.3) and [renv](https://rstudio.github.io/renv/).
2. Clone the repo and restore packages:

   ```bash
   git clone https://github.com/ckrusemd/danish-electricity-prices.git
   cd danish-electricity-prices
   ```

   In R:

   ```r
   renv::restore()
   ```

3. Render the book:

   ```r
   bookdown::render_book("index.Rmd", output_dir = "_site")

## Notebooks

The repository contains one notebook per Danish bidding zone:

- `EAST.ipynb` covers DK2 (East Denmark).
- `WEST.ipynb` covers DK1 (West Denmark) and is adapted from the EAST analysis
  so both notebooks use the same calculations and presentation.

The notebooks are companion analyses; the Bookdown R Markdown files remain the
authoritative GitHub Pages publication. Restore the `renv` environment before
opening either notebook, and rerun the data cells when you need fresh prices.
Notebook outputs are intentionally cleared from version control so the files do
not present stale prices as current data.
   ```

## Data Source

All electricity price data comes from the public [Energi Data Service DayAheadPrices API](https://api.energidataservice.dk/dataset/DayAheadPrices) — no API key required. The site normalizes the current 15-minute market data to hourly values for the legacy Bookdown charts. The site reports wholesale spot prices separately from any estimated consumer-price calculation because grid tariffs depend on the distribution network and can change over time.

## License

MIT
