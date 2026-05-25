###############################################################################
# 04_analysis_18.R
# -----------------------------------------------------------------------------
# Produces all analytical plots for the XVIII Italian Legislature (2018-2022).
# Loads pre-computed MCMC sessions from 03_mcmc_18.R.
#
# Input:  session_18.RData       (id_18, rc_18, data18)
#         sensitivity_18.RData   (id_1_18, id_2_18, id_3_18)
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
load("session_18.RData")
load("sensitivity_18.RData")

# ------------ SHARED COLOR PALETTE
# Extract unique parties and assign consistent colors across all plots
all_parties <- sort(unique(c(
  "FdI", "FI", "IPF-IC", "M5S", "MISTO", "IV", "Lega", "PD", "LEU-ART1-SI",
  "PD-IDP", "AZ-PER-RE", "AVS", "IV-C-RE", "NM"
)))

master_colors <- setNames(
  scales::viridis_pal(option = "turbo")(length(all_parties)),
  all_parties
)
###############################################################################
# PLOT A — Ideological Distribution (no CI, 2D jitter)
###############################################################################

plot_df_18 <- data.frame(
  legis.name = rownames(id_18$xbar),
  Estimate   = as.numeric(id_18$xbar[, 1]),
  stringsAsFactors = FALSE
)
plot_df_18 <- merge(plot_df_18, data18[, c("legis.name", "partito")],
                    by = "legis.name", all.x = TRUE)

set.seed(42)
ggplot(plot_df_18, aes(x = Estimate, y = 0, color = partito)) +
  geom_jitter(size = 2, alpha = 0.65, height = 0.15) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_vline(xintercept = 0, linewidth = 0.8, color = "black") +
  scale_color_manual(values = master_colors) +
  theme_minimal() +
  labs(title    = "Ideological Distribution — XVIII Legislature",
       subtitle = "Posterior means | Anchors: Fratoianni = -1, Lollobrigida = +1",
       y        = "",
       color    = "Party") +
  theme(axis.text.y       = element_blank(),
        axis.ticks.y      = element_blank(),
        panel.grid.major.y = element_blank(),
        legend.position   = "bottom")

###############################################################################
# PLOT B — Low-Voter CI Plot
# 3 least-voting members per party
# Y axis: party | X axis: ideal point | grey circle size = CI half-width
###############################################################################

# Compute posterior means and 95% credible intervals
ci_df_18 <- data.frame(
  legis.name = rownames(id_18$xbar),
  mean       = as.numeric(id_18$xbar[, 1]),
  lower      = apply(id_18$x[, , 1], 2, quantile, 0.025),
  upper      = apply(id_18$x[, , 1], 2, quantile, 0.975),
  stringsAsFactors = FALSE
)
ci_df_18$ci_width <- ci_df_18$upper - ci_df_18$lower

# Attach party and vote count
votes_per_leg_18 <- rowSums(!is.na(rc_18$votes))
votes_df_18 <- data.frame(
  legis.name = names(votes_per_leg_18),
  n_votes    = as.numeric(votes_per_leg_18),
  stringsAsFactors = FALSE
)
ci_df_18 <- merge(ci_df_18, data18[, c("legis.name", "partito")],
                  by = "legis.name", all.x = TRUE)
ci_df_18 <- merge(ci_df_18, votes_df_18, by = "legis.name", all.x = TRUE)

# Select 3 least-voting members per party
low_voters_18 <- ci_df_18 %>%
  group_by(partito) %>%
  slice_min(order_by = n_votes, n = 3, with_ties = FALSE) %>%
  ungroup()

# Slight jitter on Y within party for readability
set.seed(42)
low_voters_18$y_jitter <- as.numeric(as.factor(low_voters_18$partito)) +
  runif(nrow(low_voters_18), -0.2, 0.2)

# Scaling factor for CI size — adjust if circles are too large/small
ci_scale <- 15

ggplot(low_voters_18) +
  geom_vline(xintercept = 0, linewidth = 1.2, color = "black") +
  # Grey circle: size proportional to CI half-width
  geom_point(aes(x = mean, y = y_jitter,
                 size = ci_width * ci_scale),
             color = "grey70", alpha = 0.4) +
  # Colored circle: posterior mean
  geom_point(aes(x = mean, y = y_jitter, color = partito),
             size = 2.5) +
  scale_color_manual(values = master_colors) +
  scale_size_identity() +
  scale_y_continuous(
    breaks = seq_along(levels(as.factor(low_voters_18$partito))),
    labels = levels(as.factor(low_voters_18$partito))
  ) +
  theme_minimal() +
  labs(title    = "Posterior Uncertainty — 3 Least-Voting Members per Party (XVIII)",
       subtitle = "Grey circle radius = 95% CI half-width | Colored dot = posterior mean",
       x        = "← Left          Right →",
       y        = "",
       color    = "Party") +
  guides(size = "none") +
  theme(legend.position = "bottom")

###############################################################################
# PLOT C — Sensitivity Scatterplots with Regression Line
###############################################################################

ideal_comp_18 <- data.frame(
  legis.name = rownames(id_1_18$xbar),
  Tight      = as.numeric(id_1_18$xbar[, 1]),
  Default    = as.numeric(id_2_18$xbar[, 1]),
  Flat       = as.numeric(id_3_18$xbar[, 1]),
  stringsAsFactors = FALSE
)
ideal_comp_18 <- merge(ideal_comp_18, data18[, c("legis.name", "partito")],
                       by = "legis.name", all.x = TRUE)

p_c1 <- ggplot(ideal_comp_18, aes(x = Tight, y = Default, color = partito)) +
  geom_point(alpha = 0.5, size = 1.5) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
  geom_smooth(method = "lm", se = FALSE, color = "red", linewidth = 0.8,
              aes(group = 1)) +
  scale_color_manual(values = master_colors, guide = "none") +
  theme_minimal() +
  labs(title = "Tight (Var=1) vs Default (Var=25)",
       x = "Ideal Point (Tight)", y = "Ideal Point (Default)")

p_c2 <- ggplot(ideal_comp_18, aes(x = Default, y = Flat, color = partito)) +
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
  plot_annotation(title    = "Sensitivity to Bill Prior Specification — XVIII Legislature",
                  subtitle = "Dashed line: identity | Red line: OLS fit")

###############################################################################
# PLOT D — Beta Distribution
###############################################################################

beta_df_18 <- data.frame(
  vote_id = 1:nrow(id_18$betabar),
  beta    = id_18$betabar[, 1]
)
noisy_pct_18 <- round(mean(abs(beta_df_18$beta) < 0.5) * 100, 1)

ggplot(beta_df_18, aes(x = beta)) +
  geom_histogram(aes(y = after_stat(density)), bins = 50, fill = "steelblue", color = "white") +
  geom_vline(xintercept = 0, yintercept = 0 , linetype = "solid", color = "red", linewidth = 0.8) +
  theme_minimal() +
  geom_density(fill = "orange", alpha = 0.2, 
               color = "black", linewidth = 0.8, adjust = 1.5) +
  labs(title    = "Distribution of Bill Discrimination Parameters (β) — XVIII Legislature",
       subtitle = paste0("Votes with |β| < 0.5: ", noisy_pct_18, "%"),
       x        = "β (Discrimination Parameter)",
       y        = "Number of Votes")

###############################################################################
# PLOT E — CI Width vs Votes Cast
###############################################################################

# Recompute ci_df_18 with all legislators (not just low-voters)
ci_all_18 <- data.frame(
  legis.name = rownames(id_18$xbar),
  mean       = as.numeric(id_18$xbar[, 1]),
  lower      = apply(id_18$x[, , 1], 2, quantile, 0.025),
  upper      = apply(id_18$x[, , 1], 2, quantile, 0.975),
  stringsAsFactors = FALSE
)
ci_all_18$ci_width <- ci_all_18$upper - ci_all_18$lower
ci_all_18 <- merge(ci_all_18, votes_df_18, by = "legis.name", all.x = TRUE)
ci_all_18 <- merge(ci_all_18, data18[, c("legis.name", "partito")],
                   by = "legis.name", all.x = TRUE)

ggplot(ci_all_18, aes(x = n_votes, y = ci_width, color = partito)) +
  geom_point(alpha = 0.5, size = 1.8) +
  geom_smooth(method = "loess", se = FALSE, color = "black",
              linewidth = 0.8, aes(group = 1)) +
  scale_color_manual(values = master_colors) +
  theme_minimal() +
  labs(title    = "Posterior Precision vs Data Availability — XVIII Legislature",
       subtitle = "More votes → narrower credible interval",
       x        = "Number of Votes Cast",
       y        = "95% CI Width",
       color    = "Party") +
  theme(legend.position = "bottom")
###############################################################################
# PLOT F - Alpha/Beta Plot
###############################################################################
# beta (x axis): discrimination — how strongly a vote separates left from right
# alpha (y axis): difficulty — the threshold a legislator must exceed to vote Yea
# Votes in the top-right and bottom-left quadrants are both highly discriminating
# AND have an extreme threshold — these are the most ideologically loaded votes.
beta_alpha_df_18 <- data.frame(
  vote_id = 1:nrow(id_18$betabar),
  beta    = id_18$betabar[, 1],   # discrimination parameter
  alpha   = id_18$betabar[, 2]    # difficulty parameter
)

ggplot(beta_alpha_df_18, aes(x = beta, y = alpha)) +
  geom_point(alpha = 1, size = 2, color = "black") +
  geom_vline(xintercept = 0, linetype = "dashed",
             color = "red", linewidth = 0.6) +
  # Filled contours show density structure — adjust controls smoothness,
  # increase if contours look too jagged, decrease if too smooth
  geom_density_2d_filled(alpha = 0.4, adjust = 1) +
  geom_hline(yintercept = 0, linetype = "dashed",
             color = "red", linewidth = 0.6) +
  theme_minimal() +
  labs(title    = "Bill Discrimination vs Difficulty — XVIII Legislature",
       subtitle = "Each point is one roll-call vote | Contours show density of votes",
       x        = "β (Discrimination — ideological loading)",
       y        = "α (Difficulty — voting threshold)") +
  # The filled contour legend is not very readable — suppress it
  guides(fill = "none")