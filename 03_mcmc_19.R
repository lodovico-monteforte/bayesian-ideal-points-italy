###############################################################################
# 03_mcmc_19.R
# -----------------------------------------------------------------------------
# Bayesian ideal point estimation for the XIX Italian Legislature (2022-present)
# using the Clinton, Jackman & Rivers (2004) item-response model via pscl::ideal.
#
# Input:  matrice_19.csv         (produced by 02_preprocessing_19.py)
# Output: session_19.RData       (id_19, rc_19, data19)
#         sensitivity_19.RData   (id_1_19, id_2_19, id_3_19)
#
# Note: This script is intended to be run ONCE. All plots and further analysis
#       are handled in 04_analysis_19.R, which loads the saved sessions.
#       Run time: approximately 45-60 minutes depending on hardware.
###############################################################################

# ------------ LIBRARIES
library(pscl)
library(coda)

# ------------ ENVIRONMENT CLEANUP
rm(list = ls())
cat("\014")
graphics.off()

# ------------ DATA LOADING
# Uses a relative path — requires the working directory to be set to the project root.
# If using RStudio, open the project via BAYESIAN REPLICA.Rproj before running.
# If running from the terminal, cd into the project folder first.
data19     <- read.csv("matrice_19.csv", header = TRUE, check.names = FALSE)
vote_dt_19 <- data19[, 3:ncol(data19)]

# Sanity check: no duplicate legislator names
n_dupes <- sum(duplicated(data19$legis.name))
if (n_dupes > 0) warning(paste(n_dupes, "duplicate legislator names found."))

# ------------ ROLLCALL OBJECT
rc_19 <- rollcall(vote_dt_19,
                  yea         = 1,
                  nay         = 0,
                  missing     = NA,
                  notInLegis  = 9,
                  legis.names = data19$legis.name,
                  source      = "https://dati.camera.it/")

# ------------ ANCHOR CONSTRAINTS
# Global identification requires fixing at least two legislators on the scale.
# We use Fratoianni (far-left) = -1 and Lollobrigida (far-right) = +1.
# Both are long-standing members of their respective parties with stable
# ideological records, making them suitable anchors.
# Precision of 1e10 effectively fixes them at their prior mean.
n_leg   <- rc_19$n
xp_mat  <- matrix(0, nrow = n_leg, ncol = 1)
xpv_mat <- matrix(1, nrow = n_leg, ncol = 1)

idx_lollo <- which(rownames(rc_19$votes) == "LOLLOBRIGIDA FRANCESCO")
idx_frato <- which(rownames(rc_19$votes) == "FRATOIANNI NICOLA")

xp_mat[idx_lollo]  <-  1;  xpv_mat[idx_lollo] <- 1e10
xp_mat[idx_frato]  <- -1;  xpv_mat[idx_frato] <- 1e10

# ------------ PRIOR SPECIFICATIONS
priors_1_19 <- list(xp = xp_mat, xpv = xpv_mat, bp = 0, bpv = 1)      # Tight   (Var = 1)
priors_2_19 <- list(xp = xp_mat, xpv = xpv_mat, bp = 0, bpv = 0.04)   # Default (Var = 25)
priors_3_19 <- list(xp = xp_mat, xpv = xpv_mat, bp = 0, bpv = 0.0016) # Flat    (Var = 625)

# ------------ SENSITIVITY ANALYSIS
# Three short runs with different bill prior variances to assess
# how sensitive ideal point estimates are to prior specification.
# lop = 0 here (no vote filtering) to keep sensitivity runs comparable.
# See Jackman (2001) for motivation.
# store.item = TRUE retained for all runs to enable posterior analysis.
cat("Running sensitivity analysis (3 short runs)...\n")

id_1_19 <- ideal(rc_19,
                 codes      = rc_19$codes,
                 dropList   = list(codes = "notInLegis", lop = 0),
                 d          = 1,
                 maxiter    = 20000,
                 thin       = 25,
                 burnin     = 2000,
                 impute     = FALSE,
                 normalize  = FALSE,
                 priors     = priors_1_19,
                 startvals  = "eigen",
                 store.item = TRUE)

id_2_19 <- ideal(rc_19,
                 codes      = rc_19$codes,
                 dropList   = list(codes = "notInLegis", lop = 0),
                 d          = 1,
                 maxiter    = 20000,
                 thin       = 25,
                 burnin     = 2000,
                 impute     = FALSE,
                 normalize  = FALSE,
                 priors     = priors_2_19,
                 startvals  = "eigen",
                 store.item = TRUE)

id_3_19 <- ideal(rc_19,
                 codes      = rc_19$codes,
                 dropList   = list(codes = "notInLegis", lop = 0),
                 d          = 1,
                 maxiter    = 20000,
                 thin       = 25,
                 burnin     = 2000,
                 impute     = FALSE,
                 normalize  = FALSE,
                 priors     = priors_3_19,
                 startvals  = "eigen",
                 store.item = TRUE)

save(id_1_19, id_2_19, id_3_19, file = "sensitivity_19.RData")
cat("Sensitivity runs saved to sensitivity_19.RData\n\n")

# ------------ MAIN ESTIMATION: 1D
# Constrained start values for identification stability.
# A 1D specification is used for both legislatures: the distribution of bill
# discrimination parameters (beta) shows a low proportion of near-zero values,
# indicating that a single left-right dimension captures most voting structure.
cat("Running main 1D estimation...\n")

cl_list_19 <- list("FRATOIANNI NICOLA"      = -1,
                   "LOLLOBRIGIDA FRANCESCO"  =  1)
cl_obj_19  <- constrain.legis(rc_19,
                               x        = cl_list_19,
                               d        = 1,
                               dropList = list(codes = "notInLegis", lop = 0.05))

id_19 <- ideal(rc_19,
               codes      = rc_19$codes,
               dropList   = list(codes = "notInLegis", lop = 0.05),
               d          = 1,
               maxiter    = 130000,
               thin       = 100,
               burnin     = 30000,
               impute     = FALSE,
               normalize  = TRUE,
               priors     = priors_2_19,
               startvals  = cl_obj_19,
               store.item = TRUE)

cat("1D estimation complete.\n\n")

# ------------ SAVE MAIN SESSION
save(id_19, rc_19, data19,
     file = "session_19.RData")
cat("Main session saved to session_19.RData\n\n")

# ------------ GEWEKE CONVERGENCE DIAGNOSTICS
# Geweke test compares the mean of the first 10% and last 50% of the chain.
# |Z| > 1.96 indicates failure to converge at the 5% level.
cat("Running Geweke diagnostics...\n")

leg_19   <- as.mcmc(id_19$x[, , 1])
beta_19  <- as.mcmc(id_19$beta[, , 1])
alpha_19 <- as.mcmc(id_19$beta[, , 2])

gw_leg_19   <- geweke.diag(leg_19)
gw_beta_19  <- geweke.diag(beta_19)
gw_alpha_19 <- geweke.diag(alpha_19)

fail_leg_19   <- gw_leg_19$z[abs(gw_leg_19$z)     > 1.96]
fail_beta_19  <- gw_beta_19$z[abs(gw_beta_19$z)   > 1.96]
fail_alpha_19 <- gw_alpha_19$z[abs(gw_alpha_19$z) > 1.96]

cat("--- Geweke Results (XIX, 1D) ---\n")
cat("Failed legislators: ", length(fail_leg_19),   "out of", id_19$n, "\n")
cat("Failed beta:        ", length(fail_beta_19),  "out of", id_19$m, "\n")
cat("Failed alpha:       ", length(fail_alpha_19), "out of", id_19$m, "\n")
