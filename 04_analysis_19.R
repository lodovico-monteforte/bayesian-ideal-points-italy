###############################################################################
# 04_analysis_19.R
# -----------------------------------------------------------------------------
# Produces all analytical plots for the XIX Italian Legislature (2022-present).
# Loads pre-computed MCMC sessions from 03_mcmc_19.R.
#
# Input:  session_19.RData       (id_19, rc_19, data19)
#         sensitivity_19.RData   (id_1_19, id_2_19, id_3_19)
#
# Output: plots rendered to screen (copy into Rmd as needed)
###############################################################################

# ------------ LIBRARIES
library(ggplot2)
library(ggrepel)
library(tidyr)
library(dplyr)
library(coda)
library(patchwork)

# ------------ LOAD SESSIONS
load("session_19.RData")
load("sensitivity_19.RData")

# ------------ SHARED COLOR PALETTE
all_parties <- sort(unique(c(
  "FdI", "FI", "IPF-IC", "M5S", "MISTO", "IV", "Lega", "PD", "LEU-ART1-SI",
  "PD-IDP", "AZ-PER-RE", "AVS", "IV-C-RE", "NM"
)))

master_colors <- setNames(
  scales::viridis_pal(option = "turbo")(length(all_parties)),
  all_parties
)
###############################################################################
# PLOT A — Ideological Distribution 
###############################################################################

plot_df_19 <- data.frame(
  legis.name = rownames(id_19$xbar),
  Estimate   = as.numeric(id_19$xbar[, 1]),
  stringsAsFactors = FALSE
)
plot_df_19 <- merge(plot_df_19, data19[, c("legis.name", "partito")],
                    by = "legis.name", all.x = TRUE)

set.seed(42)
ggplot(plot_df_19, aes(x = Estimate, y = 0, color = partito)) +
  geom_jitter(size = 2, alpha = 0.65, height = 0.15) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_vline(xintercept = 0, linewidth = 0.8, color = "black") +
  scale_color_manual(values = master_colors) +
  theme_minimal() +
  labs(title    = "Ideological Distribution — XIX Legislature",
       subtitle = "Posterior means | Anchors: Fratoianni = -1, Lollobrigida = +1",
       y        = "",
       color    = "Party") +
  theme(axis.text.y        = element_blank(),
        axis.ticks.y       = element_blank(),
        panel.grid.major.y = element_blank(),
        legend.position    = "bottom")

###############################################################################
# PLOT B — Low-Voter CI Plot
# 3 least-voting members per party
# Y axis: party | X axis: ideal point | grey circle size = CI half-width
###############################################################################

ci_df_19 <- data.frame(
  legis.name = rownames(id_19$xbar),
  mean       = as.numeric(id_19$xbar[, 1]),
  lower      = apply(id_19$x[, , 1], 2, quantile, 0.025),
  upper      = apply(id_19$x[, , 1], 2, quantile, 0.975),
  stringsAsFactors = FALSE
)
ci_df_19$ci_width <- ci_df_19$upper - ci_df_19$lower

votes_per_leg_19 <- rowSums(!is.na(rc_19$votes))
votes_df_19 <- data.frame(
  legis.name = names(votes_per_leg_19),
  n_votes    = as.numeric(votes_per_leg_19),
  stringsAsFactors = FALSE
)

ci_df_19 <- merge(ci_df_19, data19[, c("legis.name", "partito")],
                  by = "legis.name", all.x = TRUE)
ci_df_19 <- merge(ci_df_19, votes_df_19, by = "legis.name", all.x = TRUE)

low_voters_19 <- ci_df_19 %>%
  group_by(partito) %>%
  slice_min(order_by = n_votes, n = 3, with_ties = FALSE) %>%
  ungroup()

set.seed(42)
low_voters_19$y_jitter <- as.numeric(as.factor(low_voters_19$partito)) +
  runif(nrow(low_voters_19), -0.2, 0.2)

# Scaling factor for CI size — adjust if circles are too large/small
ci_scale <- 15

ggplot(low_voters_19) +
  geom_vline(xintercept = 0, linewidth = 1.2, color = "black") +
  geom_point(aes(x = mean, y = y_jitter,
                 size = ci_width * ci_scale),
             color = "grey70", alpha = 0.4) +
  geom_point(aes(x = mean, y = y_jitter, color = partito),
             size = 2.5) +
  scale_color_manual(values = master_colors) +
  scale_size_identity() +
  scale_y_continuous(
    breaks = seq_along(levels(as.factor(low_voters_19$partito))),
    labels = levels(as.factor(low_voters_19$partito))
  ) +
  theme_minimal() +
  labs(title    = "Posterior Uncertainty — 3 Least-Voting Members per Party (XIX)",
       subtitle = "Grey circle radius = 95% CI half-width | Colored dot = posterior mean",
       x        = "← Left          Right →",
       y        = "",
       color    = "Party") +
  guides(size = "none") +
  theme(legend.position = "bottom")

###############################################################################
# PLOT C — Sensitivity Scatterplots with Regression Line
###############################################################################

ideal_comp_19 <- data.frame(
  legis.name = rownames(id_1_19$xbar),
  Tight      = as.numeric(id_1_19$xbar[, 1]),
  Default    = as.numeric(id_2_19$xbar[, 1]),
  Flat       = as.numeric(id_3_19$xbar[, 1]),
  stringsAsFactors = FALSE
)
ideal_comp_19 <- merge(ideal_comp_19, data19[, c("legis.name", "partito")],
                       by = "legis.name", all.x = TRUE)

p_c1 <- ggplot(ideal_comp_19, aes(x = Tight, y = Default, color = partito)) +
  geom_point(alpha = 0.5, size = 1.5) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
  geom_smooth(method = "lm", se = FALSE, color = "red", linewidth = 0.8,
              aes(group = 1)) +
  scale_color_manual(values = master_colors, guide = "none") +
  theme_minimal() +
  labs(title = "Tight (Var=1) vs Default (Var=25)",
       x = "Ideal Point (Tight)", y = "Ideal Point (Default)")

p_c2 <- ggplot(ideal_comp_19, aes(x = Default, y = Flat, color = partito)) +
  geom_point(alpha = 0.5, size = 1.5) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
  geom_smooth(method = "lm", se = FALSE, color = "red", linewidth = 0.8,
              aes(group = 1)) +
  scale_color_manual(values = master_colors) +
  theme_minimal() +
  labs(title = "Default (Var=25) vs Flat (Var=625)",
       x = "Ideal Point (Default)", y = "Ideal Point (Flat)")

p_c1 + p_c2 +
  plot_layout(guides = "collect") &
  theme(legend.position = "bottom") &
  plot_annotation(title    = "Sensitivity to Bill Prior Specification — XIX Legislature",
                  subtitle = "Dashed line: identity | Red line: OLS fit")

###############################################################################
# PLOT D — Beta Distribution
###############################################################################

beta_df_19 <- data.frame(
  vote_id = 1:nrow(id_19$betabar),
  beta    = id_19$betabar[, 1]
)
noisy_pct_19 <- round(mean(abs(beta_df_19$beta) < 0.5) * 100, 1)

ggplot(beta_df_19, aes(x = beta)) +
  geom_histogram(aes(y = after_stat(density)), bins = 50, fill = "steelblue", color = "white") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "red", linewidth = 0.8) +
  geom_density( fill = "orange", alpha = 0.2, 
               color = "black", linewidth = 0.8, adjust = 1.5) +
  theme_minimal() +
  labs(title    = "Distribution of Bill Discrimination Parameters (β) — XIX Legislature",
       subtitle = paste0("Votes with |β| < 0.5: ", noisy_pct_19, "%"),
       x        = "β (Discrimination Parameter)",
       y        = "Number of Votes")

###############################################################################
# PLOT E — CI Width vs Votes Cast
###############################################################################

ci_all_19 <- data.frame(
  legis.name = rownames(id_19$xbar),
  mean       = as.numeric(id_19$xbar[, 1]),
  lower      = apply(id_19$x[, , 1], 2, quantile, 0.025),
  upper      = apply(id_19$x[, , 1], 2, quantile, 0.975),
  stringsAsFactors = FALSE
)
ci_all_19$ci_width <- ci_all_19$upper - ci_all_19$lower
ci_all_19 <- merge(ci_all_19, votes_df_19, by = "legis.name", all.x = TRUE)
ci_all_19 <- merge(ci_all_19, data19[, c("legis.name", "partito")],
                   by = "legis.name", all.x = TRUE)

ggplot(ci_all_19, aes(x = n_votes, y = ci_width, color = partito)) +
  geom_point(alpha = 0.5, size = 1.8) +
  geom_smooth(method = "loess", se = FALSE, color = "black",
              linewidth = 0.8, aes(group = 1)) +
  scale_color_manual(values = master_colors) +
  theme_minimal() +
  labs(title    = "Posterior Precision vs Data Availability — XIX Legislature",
       subtitle = "More votes → narrower credible interval",
       x        = "Number of Votes Cast",
       y        = "95% CI Width",
       color    = "Party") +
  theme(legend.position = "bottom")

###############################################################################
# PLOT F — ALPHA/BETA PLOT
###############################################################################

beta_alpha_df_19 <- data.frame(
  vote_id = 1:nrow(id_19$betabar),
  beta    = id_19$betabar[, 1],   # discrimination parameter
  alpha   = id_19$betabar[, 2]    # difficulty parameter
)

ggplot(beta_alpha_df_19, aes(x = beta, y = alpha)) +
  # Points kept but very transparent — gives a sense of individual votes
  # without overwhelming the contour structure
  geom_point(alpha = 1, size = 1, color = "black") +
  # Filled contours show density structure — adjust controls smoothness,
  # increase if contours look too jagged, decrease if too smooth
  geom_density_2d_filled(alpha = 0.4, adjust = 1.5) +
  geom_vline(xintercept = 0, linetype = "dashed",
             color = "red", linewidth = 0.6) +
  geom_hline(yintercept = 0, linetype = "dashed",
             color = "red", linewidth = 0.6) +
  theme_minimal() +
  labs(title    = "Bill Discrimination vs Difficulty — XVIII Legislature",
       subtitle = "Each point is one roll-call vote | Contours show density of votes",
       x        = "β (Discrimination — ideological loading)",
       y        = "α (Difficulty — voting threshold)") +
  # The filled contour legend is not very readable — suppress it
  guides(fill = "none")
