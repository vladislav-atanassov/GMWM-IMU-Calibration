# E02: GMWM with simts (external/simts), SMAC-Group's R package, on E01's data and model.
# simts computes the wavelet variance, its weights and the objective, and its optimiser fits.
# It fits from simts's own answer and from a grid of starts as in matlab/wavelets/gmwm_start.m,
# keeping the lowest objective, because simts's own starting values can stop far from the
# optimum (README.md). The parameter intervals and the
# goodness-of-fit test use the full covariance of the wavelet variance, bootstrapped from the fit.
# Run from the repository root with: python experiments/run.py E02

exp_package(exp_path("external/simts"))
cfg <- exp_config()
d <- exp_data()
if (d$lost != 0) stop("Blocks were lost in the window, and the samples run straight across gaps")

x <- 1000 * d[[cfg$sensor]] # mdps
N <- nrow(x)
J <- floor(log2(N))             # simts uses every level that keeps coefficients
scales <- simts:::scales_cpp(J) # Haar filter widths, 2^j samples
term <- function(t) switch(t, WN = WN(), GM = AR1(), RW = RW(), stop("No simts term for ", t))
model <- Reduce(`+`, lapply(cfg$model, term)) # a sampled Gauss-Markov process is an AR(1)
desc <- model$desc
objdesc <- model$obj.desc
axes <- c("x", "y", "z")
z <- qnorm(0.975)
cat(sprintf("%s, %s s: %d samples at %g Hz, %d scales up to %.0f s\n", d$dataset, d$window_s, N, d$fs, J,
            2^J / d$fs))

# Starting values from the wavelet variance alone, as gmwm_start.m: the AR(1) correlation times
# on a grid of scales, the other terms from the finest or the coarsest scale. The k starts with
# the lowest objective come back as rows, best first
grid_starts <- function(nu2, objective, k) {
  tcs <- combn(scales[seq(2, J - 1, by = 2)], sum(desc == "AR1")) # columns of increasing tc [samples]
  P <- t(apply(tcs, 2, function(tc) {
    a <- 0
    unlist(lapply(desc, function(t) switch(t,
      WN = nu2[1] * scales[1],
      RW = 12 * nu2[J] / scales[J],
      AR1 = {
        a <<- a + 1
        phi <- exp(-1 / tc[a])
        c(phi, 4 * nu2[scales == tc[a]] * (1 - phi^2))
      })))
  }))
  P[order(apply(P, 1, objective))[seq_len(min(k, nrow(P)))], , drop = FALSE]
}

# simts's optimiser from theta, then again from its answer while the objective still falls
fit_from <- function(theta, nu2, omega, objective) {
  obj <- objective(theta)
  if (!is.finite(obj)) obj <- Inf
  for (k in 1:4) {
    th <- tryCatch(as.numeric(simts:::gmwm_engine(theta, desc, objdesc, "imu", nu2, omega, scales, FALSE)),
                   error = function(e) NULL)
    if (is.null(th)) break
    o <- objective(th)
    if (!is.finite(o) || o >= obj) break
    still <- obj - o > 1e-9 * o
    theta <- th
    obj <- o
    if (!still) break
  }
  list(theta = theta, obj = obj)
}

# theta per sample [mdps^2] to the units in experiments/README.md, Gauss-Markov terms by
# increasing correlation time. The intervals are 95% Wald intervals from Psi, the covariance of
# theta: mapped through the transform for the terms with one parameter, and by the delta method
# for the Gauss-Markov std, which depends on both phi and sigma2. Also returns each term's plot
# label, in model order
physical <- function(theta, Psi, fs) {
  se <- sqrt(pmax(diag(Psi), 0))
  lo <- theta - z * se
  hi <- theta + z * se
  density <- function(s2) sqrt(2 * pmax(s2, 0) / fs) # one-sided: Haar WV D^2 / (2 T) at T seconds
  K <- function(g2) sqrt(pmax(g2, 0) * fs)          # the walk's std grows as K sqrt(t)
  tc <- function(phi) ifelse(phi >= 1, Inf, ifelse(phi <= 0, 0, -1 / (fs * log(phi))))
  row <- function(term, parameter, value, unit, lo, hi) {
    data.frame(term = term, parameter = parameter, value = value, unit = unit, ci_low = lo, ci_high = hi)
  }
  first <- cumsum(c(1, lengths(objdesc)))[seq_along(desc)] # where each term's parameters start
  gm <- which(desc == "AR1")
  gm <- gm[order(theta[first[gm]])]                         # by increasing phi, so increasing tc
  labels <- character(length(desc))
  P <- NULL
  for (i in which(desc == "WN")) {
    k <- first[i]
    P <- rbind(P, row("WN", "density", density(theta[k]), "mdps/sqrt(Hz)", density(lo[k]), density(hi[k])))
    labels[i] <- "white noise"
  }
  for (g in seq_along(gm)) {
    i <- gm[g]
    k <- first[i] + 0:1
    phi <- theta[k[1]]
    s2 <- theta[k[2]]
    std <- sqrt(s2 / (1 - phi^2))
    grad <- c(std * phi / (1 - phi^2), 1 / (2 * std * (1 - phi^2))) # d std / d(phi, sigma2)
    se_std <- sqrt(max(drop(grad %*% Psi[k, k] %*% grad), 0))
    name <- paste0("GM", g)
    P <- rbind(P, row(name, "tc", tc(phi), "s", tc(lo[k[1]]), tc(hi[k[1]])),
               row(name, "std", std, "mdps", max(std - z * se_std, 0), std + z * se_std))
    labels[i] <- sprintf("%s, tc %.3g s", name, tc(phi))
  }
  for (i in which(desc == "RW")) {
    k <- first[i]
    P <- rbind(P, row("RW", "K", K(theta[k]), "mdps/sqrt(s)", K(lo[k]), K(hi[k])))
    labels[i] <- "random walk"
  }
  list(P = P, labels = labels)
}

params <- NULL
wv <- NULL
fit <- NULL
gof <- NULL
starts <- NULL
panels <- list()
t2 <- 2^seq(1, J, by = 0.05) # the theory takes any scale, so the curves can be smooth
set.seed(cfg$seed)
for (a in 1:3) {
  t0 <- proc.time()[["elapsed"]]
  w <- simts:::wvar_cpp(simts:::modwt_cpp(x[, a], "haar", J, "periodic", TRUE), FALSE, 0.6, 0.05, "eta3")
  nu2 <- w[, 1]
  omega <- diag(1 / diag(simts:::fast_cov_cpp(w[, 3], w[, 2]))) # simts's weights for gmwm()
  objective <- function(th) simts:::getObjFun(th, desc, objdesc, "imu", omega, nu2, scales)

  # Starts: simts's default answer, from its own starting values, and the grid. Neither finds
  # the lowest objective on every axis, so each is fitted on and the lowest kept
  own <- tryCatch(as.numeric(gmwm(model, x[, a], model.type = "imu", seed = cfg$seed)$estimate),
                  error = function(e) NULL)
  cands <- rbind(own, grid_starts(nu2, objective, cfg$starts))
  labels <- c(if (!is.null(own)) "simts default", paste("grid", seq_len(nrow(cands) - !is.null(own))))
  fits <- lapply(seq_len(nrow(cands)), function(r) fit_from(cands[r, ], nu2, omega, objective))
  objs <- vapply(fits, `[[`, 0, "obj")
  best <- fits[[which.min(objs)]]
  theta <- best$theta
  secs <- proc.time()[["elapsed"]] - t0
  starts <- rbind(starts, data.frame(sensor = cfg$sensor, axis = axes[a], start = labels,
                                     objective_start = apply(cands, 1, objective), objective_fit = objs))
  own <- if (is.null(own)) NA else objective(own)

  # Inference: Vb, the full covariance of the wavelet variance over series simulated from the fit
  Vb <- simts:::cov_bootstrapper(theta, desc, objdesc, N, FALSE, 0.6, cfg$bootstrap, FALSE)
  A <- simts:::derivative_first_matrix(theta, desc, objdesc, scales)
  Psi <- simts:::calculate_psi_matrix(A, Vb, omega) # sandwich: the fit's weights are not inv(Vb)
  g <- simts:::gof_test(theta, desc, objdesc, "imu", scales, Vb, nu2) # refits with inv(Vb)
  ph <- physical(theta, Psi, d$fs)

  n <- nrow(ph$P)
  params <- rbind(params, cbind(data.frame(sensor = rep(cfg$sensor, n), axis = rep(axes[a], n)), ph$P))
  wv <- rbind(wv, data.frame(sensor = cfg$sensor, axis = axes[a], scale_s = scales / d$fs, nu2 = nu2,
                             ci_low = w[, 2], ci_high = w[, 3],
                             nu2_model = as.numeric(simts:::theoretical_wv(theta, desc, objdesc, scales))))
  fit <- rbind(fit, data.frame(sensor = cfg$sensor, axis = axes[a], objective = best$obj, scales = J,
                               seconds = secs))
  gof <- rbind(gof, data.frame(sensor = cfg$sensor, axis = axes[a], statistic = g[1], df = g[3], p_value = g[2],
                               bootstrap = cfg$bootstrap))

  cat(sprintf("\n%s %s: objective %.4g (simts default %.4g), %.0f s; J test %.4g on %d df, p = %.3g\n",
              cfg$sensor, axes[a], best$obj, own, secs, g[1], g[3], g[2]))
  for (r in seq_len(n)) {
    cat(sprintf("  %-4s %-8s %10.4g [%.4g, %.4g] %s\n", ph$P$term[r], ph$P$parameter[r], ph$P$value[r],
                ph$P$ci_low[r], ph$P$ci_high[r], ph$P$unit[r]))
  }

  panels[[a]] <- list(axis = axes[a], scale_s = scales / d$fs, nu2 = nu2, lo = w[, 2], hi = w[, 3],
                      model = as.numeric(simts:::theoretical_wv(theta, desc, objdesc, t2)),
                      parts = simts:::decomp_theoretical_wv(theta, desc, objdesc, t2), labels = ph$labels)
}

exp_write("params.csv", params)
exp_write("wv.csv", wv)
exp_write("fit.csv", fit)
exp_write("gof.csv", gof)
exp_write("starts.csv", starts)

exp_figure(paste0(cfg$sensor, "_wv"), function() {
  colors <- c("white noise" = "#1baf7a", GM1 = "#eda100", GM2 = "#e87ba4", GM3 = "#9b7a3c", "random walk" = "#6250d6")
  par(mfrow = c(1, 3), mar = c(4.4, 5.4, 2.2, 1), oma = c(0, 0, 2.2, 0), las = 1, mgp = c(2.6, 0.7, 0))
  pow10 <- function(side, k) axis(side, at = 10^k, labels = parse(text = paste0("10^", k)))
  for (p in panels) {
    # The data's range: the coarsest scales' intervals span decades and would flatten the rest
    plot(NA, xlim = range(t2) / d$fs, ylim = c(min(p$lo) / 5, max(p$nu2) * 5), log = "xy", axes = FALSE,
         xlab = expression("scale " * tau * " [s]"), ylab = "", main = paste0("g", p$axis))
    title(ylab = expression(nu^2 * " [mdps"^2 * "]"), line = 3.8)
    box()
    pow10(1, -2:5)
    pow10(2, -3:5)
    abline(v = 10^(-2:5), h = 10^(-3:5), col = "grey90")
    order <- order(match(sub(",.*", "", p$labels), names(colors)))
    for (c in order) {
      lines(t2 / d$fs, p$parts[, c], lty = 2, lwd = 1.3, col = colors[[sub(",.*", "", p$labels[c])]])
    }
    lines(t2 / d$fs, p$model, col = "#2a78d6", lwd = 2.2)
    arrows(p$scale_s, p$lo, p$scale_s, p$hi, angle = 90, code = 3, length = 0.02, col = "#52514e")
    points(p$scale_s, p$nu2, pch = 19, cex = 0.8, col = "#52514e")
    legend("bottomleft", c(p$labels[order], "GMWM fit (simts)", "Haar WV, 95% interval"), bg = "white",
           col = c(vapply(sub(",.*", "", p$labels[order]), function(l) colors[[l]], ""), "#2a78d6", "#52514e"),
           lty = c(rep(2, length(order)), 1, NA), lwd = c(rep(1.3, length(order)), 2.2, NA),
           pch = c(rep(NA, length(order) + 1), 19), cex = 0.85)
  }
  mtext(sprintf("%s: %s, %s s, %s, simts", Sys.getenv("EXP_ID"), d$dataset, d$window_s,
                paste(cfg$model, collapse = " + ")), outer = TRUE, cex = 1.05)
})
