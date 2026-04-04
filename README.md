# Danish Electricity Prices

Automated analysis and forecasting of Danish electricity spot prices for the East (DK2) and West (DK1) price areas.

Built as a [bookdown](https://bookdown.org/) site, deployed via GitHub Actions and published to GitHub Pages.

## Features

- Fetches hourly spot prices from the [Energidataservice API](https://www.energidataservice.dk/)
- Calculates total consumer price including transport tariffs and electricity tax (*elafgift*)
- Finds the cheapest upcoming hours and rolling time windows (2–3 hours)
- Sends push notifications via [Pushover](https://pushover.net/) with price forecasts
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
├── Renviron.site        # Environment variables (git-ignored)
├── renv.lock            # R package lockfile (renv)
└── .github/workflows/   # CI/CD — build & deploy to GitHub Pages
```

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

3. Create a `Renviron.site` file in the project root with your Pushover credentials:

   ```
   PUSHOVER_APPKEY=your_app_token
   PUSHOVER_USERKEY=your_user_key
   ```

4. Render the book:

   ```r
   bookdown::render_book("index.Rmd")
   ```

## Data Source

All electricity price data comes from the public [Energidataservice Elspotprices API](https://api.energidataservice.dk/dataset/Elspotprices) — no API key required.

## License

MIT
