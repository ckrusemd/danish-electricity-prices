plot_theme_console <- function() {
  ggplot2::theme_minimal(base_size = 11, base_family = "sans") +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "#0d2325", colour = NA),
      panel.background = ggplot2::element_rect(fill = "#0d2325", colour = NA),
      panel.grid.major = ggplot2::element_line(colour = "#244548", linewidth = 0.3),
      panel.grid.minor = ggplot2::element_blank(),
      axis.text = ggplot2::element_text(colour = "#a9bbb9"),
      axis.title = ggplot2::element_text(colour = "#9af2df", face = "bold"),
      plot.title = ggplot2::element_text(colour = "#eef6f5", face = "bold", size = 14),
      plot.subtitle = ggplot2::element_text(colour = "#a9bbb9"),
      legend.background = ggplot2::element_rect(fill = "#0d2325", colour = NA),
      legend.text = ggplot2::element_text(colour = "#a9bbb9"),
      legend.title = ggplot2::element_text(colour = "#9af2df", face = "bold"),
      plot.margin = ggplot2::margin(12, 14, 10, 12)
    )
}

plot_theme_print <- function() {
  ggplot2::theme_minimal(base_size = 11, base_family = "sans") +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), plot.title = ggplot2::element_text(face = "bold"))
}

plot_theme <- function() {
  if (knitr::is_html_output()) plot_theme_console() else plot_theme_print()
}
