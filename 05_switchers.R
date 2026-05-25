###############################################################################
# 05_switchers.R
# -----------------------------------------------------------------------------
# Identifies legislators present in both the XVIII and XIX legislatures who
# changed party affiliation, and compares their estimated ideal points.
#
# Since both legislatures use the same anchors (Fratoianni = -1,
# Lollobrigida = +1), the two scales are directly comparable.
#
# Input:  session_18.RData   (id_18, rc_18, data18)
#         session_19.RData   (id_19, rc_19, data19)
#
# Output: switcher arrow plot rendered to screen
###############################################################################

# ------------ LIBRARIES
library(ggplot2)
library(ggrepel)
library(dplyr)

# ------------ LOAD BOTH SESSIONS
load("session_18.RData")  # loads: id_18, rc_18, data18
load("session_19.RData")  # loads: id_19, rc_19, data19

# ------------ EXTRACT IDEAL POINTS
ip_18 <- data.frame(
  legis.name = rownames(id_18$xbar),
  ip_18      = as.numeric(id_18$xbar[, 1]),
  stringsAsFactors = FALSE
)

ip_19 <- data.frame(
  legis.name = rownames(id_19$xbar),
  ip_19      = as.numeric(id_19$xbar[, 1]),
  stringsAsFactors = FALSE
)

# ------------ IDENTIFY PARTY SWITCHERS
# Merge party labels from both legislatures on legislator name
party_18 <- data18[, c("legis.name", "partito")] %>%
  rename(partito_18 = partito) %>%
  distinct()

party_19 <- data19[, c("legis.name", "partito")] %>%
  rename(partito_19 = partito) %>%
  distinct()

switchers <- party_18 %>%
  inner_join(party_19,  by = "legis.name") %>%   # present in both legislatures
  filter(partito_18 != partito_19) %>%            # changed party
  inner_join(ip_18,     by = "legis.name") %>%   # attach XVIII ideal point
  inner_join(ip_19,     by = "legis.name") %>%   # attach XIX ideal point
  mutate(delta = ip_19 - ip_18)                  # signed shift

cat("\n--- Party Switchers Found:", nrow(switchers), "---\n")
print(switchers[, c("legis.name", "partito_18", "partito_19", "ip_18", "ip_19", "delta")])

# ------------ ARROW PLOT
# Each legislator is an arrow from their XVIII position (left) to XIX position (right).
# Color encodes direction of shift: blue = moved left, red = moved right.
# Legislators are sorted by magnitude of shift.

switchers <- switchers %>%
  mutate(direction = ifelse(delta > 0, "Moved Right", "Moved Left"),
         abs_delta = abs(delta)) %>%
  arrange(desc(abs_delta))

# Attach XVIII credible intervals
ci_18 <- data.frame(
  legis.name = rownames(id_18$xbar),
  lower_18   = apply(id_18$x[, , 1], 2, quantile, 0.025),
  upper_18   = apply(id_18$x[, , 1], 2, quantile, 0.975),
  stringsAsFactors = FALSE
)

switchers <- switchers %>%
  inner_join(ci_18, by = "legis.name") %>%
  # Primary: XIX position must fall outside XVIII 95% CI
  filter(ip_19 < lower_18 | ip_19 > upper_18) %>%
  # Secondary: keep only shifts above the median of significant movers
  filter(abs_delta > median(abs_delta))

# Label: name + party change
switchers$label <- paste0(switchers$legis.name)

ggplot(switchers) +
  # Arrow from XVIII to XIX ideal point
  geom_segment(aes(x     = ip_18,
                   xend  = ip_19,
                   y     = reorder(label, delta),
                   yend  = reorder(label, delta),
                   color = direction),
               arrow     = arrow(length = unit(0.25, "cm"), type = "open"),
               linewidth = 0.9) +
  # XVIII position marker
  geom_point(aes(x = ip_18,
                 y = reorder(label, delta)),
             shape = 16, size = 2.5, color = "gray40") +
  # Vertical reference line at 0
  geom_vline(xintercept = 0, linewidth = 1, color = "black") +
  scale_color_manual(values = c("Moved Right" = "#E41A1C",
                                "Moved Left"  = "#377EB8")) +
  theme_minimal() +
  labs(title    = "Ideal Point Shift for Party Switchers (XVIII → XIX)",
       subtitle = paste("Grey dot = XVIII position | Arrow tip = XIX position\n"
                        ),
       x        = "",
       y        = "",
       color    = "Direction") +
  theme(legend.position  = "bottom",
        axis.text.y      = element_text(size = 8),
        panel.grid.major.y = element_line(color = "gray90"))

list("delta")