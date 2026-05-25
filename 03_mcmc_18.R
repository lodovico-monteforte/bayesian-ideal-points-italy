###############################################################################
# 03_mcmc_18.R
# -----------------------------------------------------------------------------
# Bayesian ideal point estimation for the XVIII Italian Legislature (2018-2022)
# using the Clinton, Jackman & Rivers (2004) item-response model via pscl::ideal.
#
# Input:  matrice_18.csv         (produced by 02_preprocessing_18.py)
# Output: session_18.RData       (id_18_1D, id_18_2D, rc_18, data18)
#         sensitivity_18.RData   (id_1, id_2, id_3)
#
# Note: This script is intended to be run ONCE. All plots and further analysis
#       are handled in 04_analysis_18.R, which loads the saved sessions.
#       Run time: approximately 60-90 minutes depending on hardware and eventual 
#       modifications on the maxiter item.
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
# If running from the terminal, cd into the project folder first

data18     <- read.csv("matrice_18.csv", header = TRUE, check.names = FALSE)
vote_dt_18 <- data18[, 3:ncol(data18)]

# Sanity check: no duplicate legislator names
n_dupes <- sum(duplicated(data18$legis.name))
if (n_dupes > 0) warning(paste(n_dupes, "duplicate legislator names found."))

# ------------ ROLLCALL OBJECT
rc_18 <- rollcall(vote_dt_18,
                  yea        = 1,
                  nay        = 0,
                  missing    = NA,
                  notInLegis = 9,
                  legis.names = data18$legis.name,
                  source     = "https://dati.camera.it/")


# ------------ ANCHOR CONSTRAINTS
# Global identification requires fixing at least two legislators on the scale.
# We use Fratoianni (far-left) = -1 and Lollobrigida (far-right) = +1.
# Both are long-standing members of their respective parties with stable
# ideological records, making them suitable anchors.
# Precision of 1e10 effectively fixes them at their prior mean.
n_leg   <- rc_18$n
xp_mat  <- matrix(0, nrow = n_leg, ncol = 1)
xpv_mat <- matrix(1, nrow = n_leg, ncol = 1)

idx_lollo <- which(rownames(rc_18$votes) == "LOLLOBRIGIDA FRANCESCO")
idx_frato <- which(rownames(rc_18$votes) == "FRATOIANNI NICOLA")

xp_mat[idx_lollo]  <-  1;  xpv_mat[idx_lollo] <- 1e10
xp_mat[idx_frato]  <- -1;  xpv_mat[idx_frato] <- 1e10

# ------------ SENSITIVITY ANALYSIS
# Three short runs with different bill prior variances to assess
# how sensitive ideal point estimates are to prior specification.
# lop = 0 here (no vote filtering) to keep sensitivity runs comparable.
# See Jackman (2001) for motivation.

cat("Running sensitivity analysis (3 short runs)...\n")

priors_1 <- list(xp = xp_mat, xpv = xpv_mat, bp = 0, bpv = 1)      # Tight  (Var = 1)
priors_2 <- list(xp = xp_mat, xpv = xpv_mat, bp = 0, bpv = 0.04)   # Default (Var = 25)
priors_3 <- list(xp = xp_mat, xpv = xpv_mat, bp = 0, bpv = 0.0016) # Flat   (Var = 625)

id_1_18 <- ideal(rc_18,
              codes      = rc_18$codes,
              dropList   = list(codes = "notInLegis", lop = 0),
              d          = 1,
              maxiter    = 20000,
              thin       = 25,
              burnin     = 2000,
              impute     = FALSE,
              normalize  = FALSE,
              priors     = priors_1,
              startvals  = "eigen",
              store.item = TRUE)

id_2_18 <- ideal(rc_18,
              codes      = rc_18$codes,
              dropList   = list(codes = "notInLegis", lop = 0),
              d          = 1,
              maxiter    = 20000,
              thin       = 25,
              burnin     = 2000,
              impute     = FALSE,
              normalize  = FALSE,
              priors     = priors_2,
              startvals  = "eigen",
              store.item = TRUE)

id_3_18 <- ideal(rc_18,
              codes      = rc_18$codes,
              dropList   = list(codes = "notInLegis", lop = 0),
              d          = 1,
              maxiter    = 20000,
              thin       = 25,
              burnin     = 2000,
              impute     = FALSE,
              normalize  = FALSE,
              priors     = priors_3,
              startvals  = "eigen",
              store.item = TRUE)

save(id_1_18, id_2_18, id_3_18, file = "sensitivity_18.RData")
cat("Sensitivity runs saved to sensitivity_18.RData\n\n")

# ------------ MAIN ESTIMATION: 1D
# Constrained start values for identification stability.
cat("Running main 1D estimation...\n")

cl_list <- list("FRATOIANNI NICOLA"    = -1,
                   "LOLLOBRIGIDA FRANCESCO" =  1)
cl_obj  <- constrain.legis(rc_18,
                               x        = cl_list,
                               d        = 1,
                               dropList = list(codes = "notInLegis", lop = 0.05))

id_18 <- ideal(rc_18,
                  codes      = rc_18$codes,
                  dropList   = list(codes = "notInLegis", lop = 0.05),
                  d          = 1,
                  maxiter    = 150000,
                  thin       = 125,
                  burnin     = 40000,
                  impute     = FALSE,
                  normalize  = TRUE,
                  priors     = priors_1,
                  startvals  = cl_obj,
                  store.item = TRUE)

cat("1D estimation complete.\n\n")


# ------------ SAVE MAIN SESSION
save(id_18, rc_18, data18,
     file = "session_18.RData")
cat("Main session saved to session_18.RData\n\n")

# ------------ GEWEKE CONVERGENCE DIAGNOSTICS
# Geweke test compares the mean of the first 10% and last 50% of the chain.
# |Z| > 1.96 indicates failure to converge at the 5% level.
cat("Running Geweke diagnostics...\n")

leg_18   <- as.mcmc(id_18$x[, , 1])
beta_18  <- as.mcmc(id_18$beta[, , 1])
alpha_18 <- as.mcmc(id_18$beta[, , 2])

gw_leg_18   <- geweke.diag(leg_18)
gw_beta_18  <- geweke.diag(beta_18)
gw_alpha_18 <- geweke.diag(alpha_18)

fail_leg_18   <- gw_leg_18$z[abs(gw_leg_18$z)     > 1.96]
fail_beta_18  <- gw_beta_18$z[abs(gw_beta_18$z)   > 1.96]
fail_alpha_18 <- gw_alpha_18$z[abs(gw_alpha_18$z) > 1.96]

cat("--- Geweke Results (XVIII, 1D) ---\n")
cat("Failed legislators: ", length(fail_leg_18),   "out of", id_18$n, "\n")
cat("Failed beta:        ", length(fail_beta_18),  "out of", id_18$m, "\n")
cat("Failed alpha:       ", length(fail_alpha_18), "out of", id_18$m, "\n")
