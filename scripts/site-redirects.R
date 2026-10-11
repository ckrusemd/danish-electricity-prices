# Actual bookdown chapter-heading slugs, plus former source-name links.
site_redirect_routes <- function() c(
  "east-denmark-dk2.html" = "east-denmark.html",
  "west-denmark-dk1.html" = "west-denmark.html",
  "heat-pump-operating-frontier.html" = "heatpump.html",
  "københavn-andel-energi-og-radius.html" = "price-components.html",
  "kobenhavn-andel-energi-og-radius.html" = "price-components.html",
  "kbenhavn-andel-energi-og-radius.html" = "price-components.html",
  "aktuelle-pris-komponenter.html" = "price-components.html",
  "EAST.html" = "east-denmark.html",
  "WEST.html" = "west-denmark.html",
  "HEATPUMP.html" = "heatpump.html",
  "PRICE_COMPONENTS.html" = "price-components.html",
  "danish-electricity-prices.html" = "index.html"
)

site_write_redirects <- function(output_dir = "_site") {
  routes <- site_redirect_routes()
  targets <- unique(unname(routes))
  if (!dir.exists(output_dir) || !all(file.exists(file.path(output_dir, targets)))) {
    stop("Render all five Quarto pages before generating compatibility redirects.", call. = FALSE)
  }
  for (alias in names(routes)) {
    target <- routes[[alias]]
    html <- paste0('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">',
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
      '<meta name="robots" content="noindex"><meta name="theme-color" content="#071719">',
      '<link rel="canonical" href="', target, '">',
      '<meta http-equiv="refresh" content="0; url=', target, '">',
      '<title>Page moved · Danish Electricity Prices</title>',
      '<style>body{background:#071719;color:#eef6f5;font:1.1rem system-ui;',
      'padding:3rem;line-height:1.6}a{color:#42e0c0}</style>',
      '<script>const anchors={"best-upcoming":"cheapest-published-window",',
      '"best-two-hour-window":"cheapest-published-window",',
      '"best-three-hour-window":"cheapest-published-window",',
      '"time-windows":"cheapest-historical-window",',
      '"last-week-upcoming":"recent-and-published-prices",',
      '"last-month-upcoming":"period-averages"};',
      'const old=location.hash.slice(1);const hash=anchors[old]?"#"+anchors[old]:location.hash;',
      'location.replace("', target, '"+location.search+hash);</script>',
      '</head><body><main><h1>This page has moved</h1><p>Continue to ',
      '<a href="', target, '">', target, '</a>.</p></main></body></html>\n')
    writeLines(html, file.path(output_dir, alias), useBytes = TRUE)
  }
  invisible(routes)
}

if (sys.nframe() == 0L) {
  output_dir <- Sys.getenv("QUARTO_PROJECT_OUTPUT_DIR", "_site")
  site_write_redirects(output_dir)
}
