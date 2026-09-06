# Danish Electricity Prices

Automated analysis and forecasting of Danish electricity spot prices for the East (DK2) and West (DK1) price areas.

Built as a [bookdown](https://bookdown.org/) site, deployed via GitHub Actions and published to GitHub Pages.

## Features

- Fetches hourly spot prices from the [Energidataservice API](https://www.energidataservice.dk/)
- Calculates total consumer price including transport tariffs and electricity tax (*elafgift*)
- Finds the cheapest upcoming hours and rolling time windows (2–3 hours)
- Builds a decision-tree model (rpart) to predict price levels by day-of-week and hour

## Project Structure

```
├── index.Rmd            # Bookdown index / landing page
├── EAST.Rmd             # Analysis for East Denmark (DK2)
├── WEST.Rmd             # Analysis for West Denmark (DK1)
├── _bookdown.yml        # Bookdown configuration
├── EAST.ipynb           # Jupyter notebook version (East)
├── EAST_new.ipynb       # Experimental notebook (East)
├── EAST_new_complete.ipynb
├── test_ir_fixed.ipynb
├── renv.lock            # R package lockfile (renv)
└── .github/workflows/   # CI/CD — build & deploy to GitHub Pages
```

## Deployment

The site is built and deployed daily by GitHub Actions and can also be run manually
from the Actions tab. The repository is intended to be public so standard GitHub
Actions runners and GitHub Pages remain free. No API key or application secrets are
required.

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
   ```

## Data Source

All electricity price data comes from the public [Energidataservice Elspotprices API](https://api.energidataservice.dk/dataset/Elspotprices) — no API key required. The site reports wholesale spot prices separately from any estimated consumer-price calculation because grid tariffs depend on the distribution network and can change over time.

## License

MIT
