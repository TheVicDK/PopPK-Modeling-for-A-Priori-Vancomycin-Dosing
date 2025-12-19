library(nlmixr2)
library(nlmixr2extra)
library(data.table)
library(parallel)
library(rxode2)
library(ggplot2)
library(GGally)
library(vpc)
library(dplyr)
library(tidyr)


# skulle gerne sørge for at der blive brugt all de kerner der kan bruges
n_cores <- parallel::detectCores(logical = FALSE)
rxode2::setRxThreads(n_cores)
options(rxode2.ciDir = "/tmp/rxcache")

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 3) {
   stop("Error: grrr ikke nok argumenter. BRUG: Rscript your_script.R <csv_path> <mode> <pdf_out path> <n_patients> (optional)")
}

csv_path <- args[1]
if (!file.exists(csv_path)) {
   stop(paste("Warning: Kunne ikke finde data csv:", csv_path))
}
event_table <- fread(csv_path)

mode_input <- tolower(args[2])
is_full_fit <- (mode_input == "all")

pdf_out <- args[3]

n_patients_input <- args[4]

if (!is_full_fit) {
   n_patients_input <- as.integer(n_patients_input)

   if (is.na(n_patients_input) || n_patients_input <= 0) {
      stop("Warning: Nu fjoller du enten er det ikke et heltal eller så er det negativt.")
   }
   n_patients <- n_patients_input
}


# event_table <- as.data.frame(event_table)
#
# event_table <- event_table %>%
#   group_by(ID) %>%
#   fill(Creatinine, gender, anchor_age, Weight,Albumin,height_cm, .direction = "downup") %>%
#   ungroup()
#
# head(event_table)
# setDT(event_table)


# her samle vi obs og dose tabeller
# event_table <- rbind(dose_rows, obs_rows)[order(ID, TIME)]
# write.csv(event_table, "test.csv")

if (!is_full_fit) {
   event_table <- event_table[ID %in% unique(ID)[1:n_patients]]
}

two_compartment <- function() {
   # init blocken er vores start "vægte"
   # de her værdier er fra gemini dem skal vi nok have noget lit der understøtter
   ini({
      # log af estimater for at vi senere kan skrive  cl <- exp(tcl + eta_cl)
      # hvis ikke skulle vi skrive cl <- tcl * exp(eta_cl) hvilket ikke matematisk er forkert
      # men de underliggende estimeringer der sker når vi fitter kan prøve værdier fra minus til plus uendelig
      # og det dur ikke med negative CL værdier det giver ingen mening

      tcl <- log(4)
      label("CL")
      tvc <- log(60)
      label("V_c")
      tq <- log(4)
      label("Q")
      tvp <- log(40)
      label("V_p")

      eta_cl ~ 0.3
      eta_vc ~ 0.3
      eta_vp ~ 0.3
      eta_q ~ 0.3
      beta_weight <- 1.0
      beta_EPI <- 1.0

      add_sd <- 0.5
      prop_sd <- 0.5
   })

   model({
      cl <- exp(tcl + eta_cl) * (eGFR_CKD_EPI/75)^beta_EPI
      vc <- exp(tvc + eta_vc) * (Weight / 84)^beta_weight
      vp <- exp(tvp + eta_vp) * (Weight / 84)^beta_weight
      q <- exp(tq + eta_q)

      cp <- linCmt()

      cp ~ add(add_sd) + prop(prop_sd)
   })
}


one_compartment <- function() {
   ini({
      tcl <- log(4)
      label("CL")
      tv <- log(60)
      label("V")

      eta_cl ~ 0.3
      eta_v ~ 0.3
      beta_weight <- 1.0
      beta_CG <- 1.0

      add_sd <- 0.5
      prop_sd <- 0.2
   })
   model({
      cl <- exp(tcl + eta_cl) * (eGFR_CG/103)^beta_CG
      v <- exp(tv + eta_v) * (Weight / 84)^beta_weight

      cp <- linCmt()

      cp ~ add(add_sd) + prop(prop_sd)
   })
}

fit <- nlmixr2(
   one_compartment,
   event_table,
   est = "saem",
   control = saemControl(
      nBurn = 200,
      nEm = 100,
      print = 10,
      handleUninformativeEtas = FALSE
   )
)

saveRDS(fit, "one_comp_fit_7_12_EPI_on_cl_allo_scale.rds")

pdf(pdf_out, width = 12, height = 13)

#############################################
# PAGE 1 — SUMMARY TEXT
#############################################

plot.new()
title("PK Model Summary")

val_aic <- tryCatch(AIC(fit), error = function(e) "NA")
val_bic <- tryCatch(BIC(fit), error = function(e) "NA")

omega_txt <- paste(capture.output(print(fit$omega)), collapse = "\n")
shrink_txt <- paste(capture.output(print(fit$shrink)), collapse = "\n")
theta_txt <- paste(capture.output(print(fit$parFixed)), collapse = "\n")

summary_text <- paste0(
   "Algorithm: ", fit$est, "\n",
   "Objective Function: ", fit$objf, "\n",
   "AIC: ", val_aic, "\n",
   "BIC: ", val_bic, "\n",
   "Converged: ", fit$message, "\n\n",
   "Subjects: ", fit$nsub, "\n",
   "Observations: ", fit$nobs, "\n",
   "Fixed Effects (Population Params):\n", theta_txt, "\n\n",
   "------------------------------------------------\n",
   "Shrinkage:\n", shrink_txt, "\n\n",
   "Omega (BSV Matrix):\n", omega_txt
)

text(0, 0.9, summary_text, adj = c(0, 1), cex = 0.8, family = "mono")

#############################################
# PAGE 2 — GOF 2×2
#############################################

plot.new()
par(mfrow = c(2, 2)) # full page layout

df <- as.data.frame(fit)
res_col <- if ("CWRES" %in% names(df)) "CWRES" else "IWRES"

# 1. DV vs PRED
plot(df$PRED, df$DV,
   xlab = "PRED", ylab = "DV", main = "DV vs PRED",
   pch = 16, col = "#83a59855"
)
abline(0, 1, col = "#cc241d", lwd = 2)

# 2. DV vs IPRED
plot(df$IPRED, df$DV,
   xlab = "IPRED", ylab = "DV", main = "DV vs IPRED",
   pch = 16, col = "#83a59855"
)
abline(0, 1, col = "#cc241d", lwd = 2)

# 3. Residuals vs TIME
plot(df$TIME, df[[res_col]],
   xlab = "TIME", ylab = res_col, main = paste(res_col, "vs TIME"),
   pch = 16, col = "#45858855"
)
abline(h = 0, col = "#cc241d", lwd = 2)

# 4. Residuals vs PRED
plot(df$PRED, df[[res_col]],
   xlab = "PRED", ylab = res_col, main = paste(res_col, "vs PRED"),
   pch = 16, col = "#45858855"
)
abline(h = 0, col = "#cc241d", lwd = 2)

par(mfrow = c(1, 1)) # reset

#############################################
# ETA PAGES — each ETA gets one full page
#############################################

etas <- as.data.frame(lapply(fit$eta, function(x) as.numeric(as.character(x))))
etas <- etas[, sapply(etas, is.numeric), drop = FALSE]
etas <- etas[, !names(etas) %in% c("ID", "id", "Id"), drop = FALSE]

for (eta_name in names(etas)) {
   plot.new()
   par(mfrow = c(2, 1)) # 2 rows: density + qq

   # Density
   plot(
      density(etas[[eta_name]]),
      main = paste("Density of", eta_name),
      xlab = "ETA value",
      col = "#83a598",
      lwd = 2
   )
   rug(etas[[eta_name]])

   # Q-Q
   qqnorm(
      etas[[eta_name]],
      main = paste("Q–Q Plot of", eta_name)
   )
   qqline(etas[[eta_name]], col = "#cc241d", lwd = 2)

   par(mfrow = c(1, 1)) # reset
}

pairs_plot <- ggpairs(
   etas,
   title = "Pairs Plot of ETA values",
   lower = list(continuous = wrap("points", alpha = 0.5, size = 1, color = "#458588")),
   diag = list(continuous = wrap("densityDiag", fill = "#83a598", alpha = 0.5)),
   upper = list(continuous = wrap("cor", size = 4))
)

print(pairs_plot)

dev.off()
