################################################################################
## Experimenting with other ideas for synth
################################################################################




get_svd_bal <- function(outcomes, metadata, trt_unit=1, r, hyperparam,
                    link=c("logit", "linear", "pos-linear"),
                    regularizer=c(NULL, "l1", "l2", "ridge", "linf"),
                    normalized=TRUE,
                    outcome_col=NULL,
                    cols=list(unit="unit", time="time",
                              outcome="outcome", treated="treated"),
                    opts=list()) {
    #' Find Balancing weights by solving the dual optimization problem
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param trt_unit Unit that is treated (target for regression), default: 0
    #' @param r Rank of matrix for SVD
    #' @param hyperparam Regularization hyperparameter
    #' @param link Link function for weights
    #' @param regularizer Dual of balance criterion
    #' @param normalized Whether to normalize the weights
    #' @param outcome_col Column name which identifies outcomes, if NULL then
    #'                    assume only one outcome
    #' @param cols Column names corresponding to the units,
    #'             time variable, outcome, and treated indicator
    #' @param opts Optimization options
    #'        \itemize{
    #'          \item{MAX_ITERS }{Maximum number of iterations to run}
    #'          \item{EPS }{Error tolerance}}
    #'
    #' @return outcomes with additional synthetic control added and weights
    #' @export

    ## format data, reduce dim with SVD and get weights
    data_out <- format_ipw(outcomes, metadata, outcome_col, cols)

    data_out$X <- svd(data_out$X)$u[,1:r,drop=FALSE]
    out <- fit_balancer_formatted(data_out$X, data_out$trt, link, regularizer,
                                  hyperparam, normalized, opts)

    ## match outcome types to synthetic controls
    if(!is.null(outcome_col)) {
        data_out$outcomes[[outcome_col]] <- factor(outcomes[[outcome_col]],
                                          levels = names(out$groups))
        data_out$outcomes <- data_out$outcomes %>% dplyr::arrange_(outcome_col)
    }

    syndat <- format_data(outcomes, metadata, trt_unit, outcome_col, cols)
    out$controls <- syndat$synth_data$Y0plot
    ctrls <- impute_controls(syndat$outcomes, out, syndat$trt_unit)
    ctrls$dual <- out$dual
    ctrls$primal_obj <- out$primal_obj
    ctrls$l1_error <- out$l1_error
    ctrls$l2_error <- out$l2_error
    ctrls$linf_error <- out$linf_error
    ctrls$pscores <- out$pscores
    ctrls$eta <- out$eta
    ctrls$feasible <- out$feasible
    ctrls$scaled_primal_obj <- out$scaled_primal_obj
    ctrls$controls <- out$controls
    return(ctrls)
}



get_svd_syn <- function(outcomes, metadata, trt_unit=1, r, unit_mean=F,
                        outcome_col=NULL,
                        cols=list(unit="unit", time="time",
                                  outcome="outcome", treated="treated")) {
    #' Find Balancing weights by solving the dual optimization problem
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param trt_unit Unit that is treated (target for regression), default: 0
    #' @param r Rank of matrix for SVD
    #' @param unit_mean Whether to take out the unit means
    #' @param outcome_col Column name which identifies outcomes, if NULL then
    #'                    assume only one outcome
    #' @param cols Column names corresponding to the units,
    #'             time variable, outcome, and treated indicator
    #'
    #' @return outcomes with additional synthetic control added and weights
    #' @export

    
    ## format into synth
    data_out <- format_data(outcomes, metadata, trt_unit, outcome_col, cols)

    out <- fit_svd_formatted(data_out, r, unit_mean)

    ## match outcome types to synthetic controls
    if(!is.null(outcome_col)) {
        data_out$outcomes[[outcome_col]] <- factor(outcomes[[outcome_col]],
                                          levels = names(out$groups))
        data_out$outcomes <- data_out$outcomes %>% dplyr::arrange_(outcome_col)
    }

    syndat <- data_out
    out$controls <- syndat$synth_data$Y0plot
    ctrls <- impute_controls(syndat$outcomes, out, syndat$trt_unit)
    ctrls$dual <- out$dual
    ctrls$primal_obj <- out$primal_obj
    ctrls$l1_error <- out$l1_error
    ctrls$l2_error <- out$l2_error
    ctrls$linf_error <- out$linf_error
    ctrls$pscores <- out$pscores
    ctrls$eta <- out$eta
    ctrls$feasible <- out$feasible
    ctrls$scaled_primal_obj <- out$scaled_primal_obj
    ctrls$controls <- out$controls
    return(ctrls)
}



fit_svd_formatted <- function(data_out, r, unit_mean) {
    #' Fit synthetic controls on outcomes after performing SVD
    #' @param data_out Panel data formatted by Synth::dataprep
    #' @param r Rank of matrix for SVD
    #' @param unit_mean Whether to take out the unit means
    
    is_treated <- data_out$is_treated
    data_out <- data_out$synth_data

    ## SVD on lagged outcomes

    ## take out column means
    comb <- t(cbind(data_out$Z1, data_out$Z0))
    comb <- apply(comb, 2, function(x) x - mean(x))
    
    if(unit_mean) {
        ## take out unit means separately
        unit_means <- rowMeans(comb)

        comb <- comb - unit_means
        svd_obj <- svd(comb)        
        if(r != 0) {
            low_dim <- (svd_obj$u %*% diag(svd_obj$d))[,1:r,drop=F]
            low_dim <- cbind(unit_means, low_dim)
        } else {
            low_dim <- t(t(unit_means))
        }

        
    } else {
        svd_obj <- svd(comb)
        low_dim <- (svd_obj$u %*% diag(svd_obj$d))[,1:r,drop=F]
    }

    ## change the "predictors" to be the pre period outcomes
    data_out$X0 <- t(low_dim[-1,,drop=FALSE])
    data_out$X1 <- t(low_dim[1,,drop=FALSE])


    ## set weights on predictors to be 0
    custom.v <- rep(1, dim(data_out$X0)[1])

    ## fit the weights    
    capture.output(synth_out <- Synth::synth(data_out,
                                             custom.v=custom.v,
                                             quadopt="LowRankQP"))
    weights <- synth_out$solution.w


    loss <- synth_out$loss.w
    primal_obj <- sqrt(sum((data_out$Z0 %*% weights - data_out$Z1)^2))
    ## primal objective value scaled by least squares difference for mean
    x <- t(data_out$Z0)
    y <- data_out$Z1
    unif_primal_obj <- sqrt(sum((t(x) %*% rep(1/dim(x)[1], dim(x)[1]) - y)^2))
    scaled_primal_obj <- primal_obj / unif_primal_obj    
    return(list(weights=weights,
                controls=data_out$Y0plot,
                is_treated=is_treated,
                primal_obj=primal_obj,
                scaled_primal_obj=scaled_primal_obj))
}

