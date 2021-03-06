#############################################################
## Methods for choosing the balance in SC
#############################################################


bin_search_ <- function(eps, feasfunc) {
    #' Perform binary search for the smallest balance which is feasible
    #' @param eps Sorted list of balance tolerances to try
    #' @param feasfunc Function which returns True if feasible
    #'
    #' @return smallest tolerance which is feasible

    if(length(eps) == 1) {
        if(feasfunc(eps[1])) {
            return(eps[1])
        } else {
            return(-1)
        }
    } else {
        ## check feasibility of middle point (rounded down)
        mid <- floor(length(eps) / 2)
        isfeas <- feasfunc(eps[mid])
        if(isfeas) {
            ## if feasible, try lower half
            return(bin_search_(eps[1:mid], feasfunc))
        } else {
            ## if not feasible try upper half
            return(bin_search_(eps[(mid+1):length(eps)], feasfunc))
        }
    }
}


bin_search <- function(start, end, by, feasfunc) {
    #' Wrapper for bin_search_ which generates tolerances to search over
    #' @param start Starting value of tolerances
    #' @param end Ending value of tolerances
    #' @param by Step size of tolerances
    #' @param feasfunc Function which returns True if feasible
    #' @export

    eps <- seq(start, end, by)
    return(bin_search_(eps, feasfunc))
}

bin_search_balancer <- function(outcomes, metadata, trt_unit=1, start, end, by,
                         link=c("logit", "linear", "pos-linear"),
                         regularizer=c("l1", "l2", "linf"),
                         normalized=TRUE,
                         outcome_col=NULL,
                         cols=list(unit="unit", time="time",
                                   outcome="outcome", treated="treated"),
                         opts=list()) {
    #' Find the minimal amount of regularization possible
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param trt_unit Unit that is treated (target for regression), default: 0
    #' @param start Starting value of tolerances
    #' @param end Ending value of tolerances
    #' @param by Step size of tolerances
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

    ## just format data once
    data_out <- format_ipw(outcomes, metadata, outcome_col, cols)

    ## create the feasibility function by changing the hyper parameter
    feasfunc <- function(param) {
        suppressMessages(
            out <-
                fit_balancer_formatted(
                    data_out$X,
                    data_out$trt,
                    link=link,
                    regularizer=regularizer,
                    param, normalized=normalized,
                    opts=opts))
        return(out$feasible)
    }
    
    ## find the best epsilon
    param <- bin_search(start, end, by, feasfunc)

    ## if it failed, then stop everything
    if(param < 0) {
        stop("Failed to find a synthetic control with balance better than 4 std deviations")
    }


    ## use this hyperparameter
    suppressMessages(out <- get_balancer(outcomes, metadata, trt_unit, param,
                                         link, regularizer, normalized,
                                         outcome_col, cols, opts))
    out$param <- param
    return(out)
    }


lexical <- function(outcomes, metadata, grp_order, outcome_col,
                    trt_unit=1, by=.1, maxep=1, 
                    cols=list(unit="unit", time="time",
                              outcome="outcome", treated="treated"),
                    lowerep=0) {
    #' Finds the lowest feasible tolerance in each group, holding
    #' the previous groups fixed
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param grp_order Lexical ordering of groups
    #' @param outcome_col Column name which identifies outcomes, if NULL then
    #'                    assume only one outcome
    #' @param trt_unit Unit that is treated (target for regression), default: 0
    #' @param by Step size for tolerances to dry, default: 0.1
    #' @param maxep Maximum tolerance to consider
    #' @param cols Column names corresponding to the units,
    #'             time variable, outcome, and treated indicator
    #'
    #' @return List with lowest tolerances lexically
    #' @export

    ## just format data once
    data_out <- format_data(outcomes, metadata, trt_unit, outcome_col, cols=cols)

    ## get the magnitdues for the controls in each group
    syn_data <- data_out$synth_data
    x <- syn_data$Z0
    groups <- data_out$groups
    mags <- lapply(groups, function(g) sqrt(sum((x[g,] - mean(x[g,]))^2)))

    ## reorder
    mags <- mags[grp_order]

    ## set original epsilon to infinity
    epslist <- lapply(grp_order, function(g) 10^20 * mags[[g]])
    names(epslist) <- grp_order

    ## iterate over groups, finding the lowest feasible tolerance
    for(g in grp_order) {

        ## create the feasibility function by keeping other tolerances fixed
        feasfunc <- function(ep) {
            epslist[[g]] <- ep
            feas <- suppressMessages(fit_entropy_formatted(data_out, epslist)$feasible)
            return(feas)
        }
        
        ## find the best epsilon
        if(g %in% names(lowerep)) {
            minep <- bin_search(lowerep[[g]], maxep, by, feasfunc)
        } else {
            minep <- bin_search(lowerep, maxep, by, feasfunc)
        }

        ## if it failed, then stop everything
        if(minep < 0) {
            break
        }
        ## keep that tolerance
        epslist[[g]] <- minep
    }

    return(epslist)
}


lexical_time <- function(outcomes, metadata, trt_unit=1, by=.1,
                         cols=list(unit="unit", time="time",
                                   outcome="outcome", treated="treated")) {
    #' Finds the lowest feasible tolerance in each time period from
    #' most recent to oldest, holding the previous times fixed
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param trt_unit Unit that is treated (target for regression), default: 0
    #' @param by Step size for tolerances to dry, default: 0.1 * magnitude
    #' @param cols Column names corresponding to the units,
    #'             time variable, outcome, and treated indicator
    #'
    #' @return List with lowest tolerances lexically
    #' @export

    ## rename columns
    newdf <- outcomes %>%
        rename_(.dots=cols) %>%
        mutate(synthetic="N",
               "potential_outcome"=ifelse(treated,"Y(1)", "Y(0)"))
                                        # add in extra columns
    ## get the times
    t_int <- metadata$t_int
    times <- rev(paste((newdf %>% filter(time < t_int) %>%
                    distinct(time) %>% select(time))$time))

    ## add a second time column to selection
    timeout <- newdf %>%
        mutate(time2=ifelse(time < (t_int-1), paste(time), paste(t_int-1)))

    ## get the lowest feasible tolerances
    time_eps <- lexical(timeout, metadata, times, "time2", trt_unit, by)

    ## fit the control
    lex <- get_entropy(timeout, metadata, trt_unit, time_eps, "time2")

    ## get rid of the second time column
    lex$outcomes <- lex$outcomes %>% select(-time2)

    return(lex)
}



recent_group <- function(outcomes, metadata, t_past,
                         trt_unit=1, by=.1, maxep=1,
                         cols=list(unit="unit", time="time",
                                   outcome="outcome", treated="treated")) {
    #' Lexically minimizes the imbalance in two groups, recent and old
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param t_past Number of recent time periods to balance especially
    #' @param trt_unit Unit that is treated (target for regression), default: 0
    #' @param by Step size for tolerances to dry, default: 0.1 * magnitude
    #' @param maxep Maximum tolerance to consider
    #' @param cols Column names corresponding to the units,
    #'             time variable, outcome, and treated indicator
    #'
    #' @return Fitted SC with lexically minimized imbalance in time groups
    #' @export
    
    ## rename columns
    newdf <- outcomes %>%
        rename_(.dots=cols) %>%
        mutate(synthetic="N",
               "potential_outcome"=ifelse(treated,"Y(1)", "Y(0)"))
                                        # add in extra columns
    
    ## add a column indicating before or after "most recent period"
    timeout <- newdf %>%
        mutate(recent=ifelse(time < t_past, "Old", "Recent"))

    ## get the lowest feasible tolerances
    time_eps <- lexical(timeout, metadata, c("Recent", "Old"), "recent", trt_unit, by, maxep)
    
    ## fit the control
    lex <- get_entropy(timeout, metadata, trt_unit, time_eps, "recent")

    ## get rid of the second time column
    lex$outcomes <- lex$outcomes %>% select(-recent)

    return(lex)
}


sep_lasso_ <- function(outcomes, metadata, trt_unit, by, scale=TRUE,
                       maxep=4, cols=list(unit="unit", time="time",
                                 outcome="outcome", treated="treated")) {
    #' Internal function that does the work of sep_lasso
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param trt_unit Unit that is treated (target for regression)
    #' @param by Step size for tolerances to try
    #' @param scale Scale imbalances by standard deviations, default: True
    #' @param maxep Maximum imbalance to consider in units of sd, default: 4
    #' @param cols Column names corresponding to the units,
    #'             time variable, outcome, and treated indicator
    #'
    #' @return List with lowest tolerances in units of standard deviation

    ## just format data once
    data_out <- format_data(outcomes, metadata, trt_unit, cols=cols)

    ## get the standard deviations of controls for each group
    syn_data <- data_out$synth_data
    x <- syn_data$Z0
    if(scale) {
        sds <- apply(x, 1, sd)
    } else {
        sds <- rep(1, dim(x)[1])
    }
    ## set original epsilon to infinity
    epslist <- sapply(sds, function(sd) 10^20 * sd)
    
    ## create the feasibility function by changing the tolerance in units of sd
    feasfunc <- function(ep) {
        epslist <- sapply(sds, function(sd) ep * sd)
        feas <- suppressMessages(fit_entropy_formatted(data_out, epslist, lasso=TRUE)$feasible)
        return(feas)
    }
    
    ## find the best epsilon
    minep <- bin_search(0, maxep, by, feasfunc)

    ## if it failed, then stop everything
    if(minep < 0) {
        stop("Failed to find a synthetic control with balance better than 4 std deviations")
    }
    ## keep that tolerance
    epslist <- lapply(sds, function(sd) minep * sd)
    return(list(epslist, minep))
    
    }


sep_lasso <- function(outcomes, metadata, trt_unit=1, by=.1,
                      scale=TRUE, maxep=4, 
                      cols=list(unit="unit", time="time",
                                outcome="outcome", treated="treated")) {
    #' Finds the lowest feasible tolerance in units of standard deviation for
    #' all time periods and covariates
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param trt_unit Unit that is treated (target for regression), default: 0
    #' @param by Step size for tolerances to dry, default: 0.1 * magnitude
    #' @param cols Column names corresponding to the units,
    #' @param scale Scale imbalances by standard deviations, default: True
    #' @param maxep Maximum imbalance to consider in units of sd, default: 4
    #'             time variable, outcome, and treated indicator
    #'
    #' @return max ent SC fit with lowest imbalance tolerance
    #' @export

    ## get the lowest global imbalance
    epslist <- sep_lasso_(outcomes, metadata, trt_unit, by, scale, maxep, cols=cols)
    ## fit the SC
    lasso_sc <- get_entropy(outcomes, metadata, trt_unit, eps=epslist[[2]], lasso=TRUE, cols=cols)

    lasso_sc$minep <- epslist[[2]]
    return(lasso_sc)
}


cv_di_bal <- function(outcomes, metadata,
                      hyperparams,
                      link=c("logit", "linear", "pos-linear"),
                      regularizer=c(NULL, "l1", "l2", "ridge", "linf"),
                      normalized=TRUE,
                      outcome_col=NULL,
                      cols=list(unit="unit", time="time",
                                   outcome="outcome", treated="treated"),
                      opts=list()) {
    #' Cross validation for balancing weights, DI style
    #' Uses the CV procedure from Doudchenko-Imbens (2017)
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param hyperparams Vector of hyper-parameter settings to consider
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


    ## format data correctly
    ipw_dat <- format_ipw(outcomes, metadata, outcome_col, cols)    
    nc <- sum(ipw_dat$trt==0)
    t0 <- ncol(ipw_dat$X)

    ## collect errors here
    errs <- matrix(0, nrow=nc, ncol=length(hyperparams))
    
    ## iterate over control units
    for(i in 1:nc) {
        newdat <- ipw_dat
        ## remove the last pre-period for validation
        ## set the treated unit to i
        newdat$X <- ipw_dat$X[ipw_dat$trt==0,-t0]
        newdat$trt <- numeric(nc)
        newdat$trt[i] <- 1
        
        ## iterate over hyper-parameter choices
        for(j in 1:length(hyperparams)) {
            ## fit weights
            suppressMessages(
                bal <- fit_balancer_formatted(newdat$X, newdat$trt, link,
                                              regularizer, hyperparam=hyperparams[j],
                                              normalized=normalized, opts=opts)
            )
            ## get the error
            errs[i,j] <- ipw_dat$X[ipw_dat$trt==0,t0][i] -
                t(ipw_dat$X[ipw_dat$trt==0,t0][-i]) %*% bal$weights
        }
        
    }
    ## get the hyperparam with the best balance and refit
    best_lam <- hyperparams[which.min(apply(errs, 2, function(x) mean(x^2)))]
    return(best_lam)
    ## bal <- get_balancer(outcomes, metadata, trt_unit, best_lam, link, regularizer, normalized, opts)
    ## bal$best_lam <- best_lam
    ## return(bal)


}



cv_kfold_bal <- function(outcomes, metadata,
                  n_folds,
                  hyperparams,
                  link=c("logit", "linear", "pos-linear"),
                  regularizer=c(NULL, "l1", "l2", "ridge", "linf"),
                  normalized=TRUE,
                  outcome_col=NULL,
                  cols=list(unit="unit", time="time",
                            outcome="outcome", treated="treated"),
                  opts=list()) {
    #' Cross validation for balancing weights
    #' K-fold cross validation, fit on K-1 folds, evaluate balance on Kth fold
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param hyperparams Vector of hyper-parameter settings to consider
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
    #' @return best hyper parameter
    #' @export


    ## format data correctly
    ipw_dat <- format_ipw(outcomes, metadata, outcome_col, cols)    
    nc <- sum(ipw_dat$trt==0)
    t0 <- ncol(ipw_dat$X)

    ## collect errors here
    errs <- matrix(0, nrow=nc, ncol=length(hyperparams))

    ## shuffle controls
    X0 <- ipw_dat$X[ipw_dat$trt==0,,drop=F]
    X0 <- X0[sample(nc),]
    X1 <- ipw_dat$X[ipw_dat$trt==1,,drop=F]

    ## get folds
    folds <- cut(1:nc, breaks=n_folds, labels=FALSE)

    ## iterate over folds
    for(i in 1:n_folds) {
        newdat <- ipw_dat

        ## remove the ith fold
        fold_inds <- which(folds == i)
        newdat$X <- rbind(X1, X0[-fold_inds, ])
        newdat$trt <- c(rep(1, nrow(X1)), rep(0, nrow(X0[-fold_inds, ])))
        ctrls <- X0[fold_inds, ]

        
        ## iterate over hyper-parameter choices
        for(j in 1:length(hyperparams)) {
            ## fit weights
            suppressMessages(
                bal <- fit_balancer_formatted(newdat$X, newdat$trt, link,
                                              regularizer, hyperparam=hyperparams[j],
                                              normalized=normalized, opts=opts)
            )
            ## get the error using held out units
            ## TODO generalize for other link functions
            new_w <- exp(ctrls %*% bal$dual)
            new_w <- new_w / sum(new_w)
            errs[i,j] <- sum((t(X1) - 
                t(ctrls)%*% new_w)^2)
        }
        
    }
    ## get the hyperparameter with the best balance and refit
    best_lam <- hyperparams[which.min(apply(errs, 2, sum))]
    return(best_lam)

}



cv_wz_bal <- function(outcomes, metadata,
                  n_boot,
                  hyperparams,
                  link=c("logit", "linear", "pos-linear"),
                  regularizer=c(NULL, "l1", "l2", "ridge", "linf"),
                  normalized=TRUE,
                  outcome_col=NULL,
                  cols=list(unit="unit", time="time",
                            outcome="outcome", treated="treated"),
                  opts=list()) {
    #' Cross validation for l2_entropy regularized synthetic controls
    #' Take bootstrap samples over the controls and evaluate balance
    #' Modified version of Wang & Zubizaretta (2018)
    #' @param outcomes Tidy dataframe with the outcomes and meta data
    #' @param metadata Dataframe of metadata
    #' @param hyperparams Vector of hyper-parameter settings to consider
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
    #' @return best hyperparameter
    #' @export

    ## format data correctly
    ipw_dat <- format_ipw(outcomes, metadata, outcome_col, cols)    
    nc <- sum(ipw_dat$trt==0)
    t0 <- ncol(ipw_dat$X)

    ## collect errors here
    errs <- matrix(0, nrow=n_boot, ncol=length(hyperparams))


    X0 <- ipw_dat$X[ipw_dat$trt==0,,drop=F]
    X1 <- ipw_dat$X[ipw_dat$trt==1,,drop=F]

    ## iterate over hyper-parameter choices
    for(j in 1:length(hyperparams)) {
        ## fit weights
        suppressMessages(
            bal <- fit_balancer_formatted(ipw_dat$X, ipw_dat$trt, link,
                                          regularizer, hyperparam=hyperparams[j],
                                          normalized=normalized, opts=opts)
        )
        ## get bootstrap samples
        for(b in 1:n_boot) {
            boots <- sample(nc, replace=TRUE)
            ctrls <- X0[boots,]
            
            ## TODO generalize for other link functions
            new_w <- exp(ctrls %*% bal$dual)
            new_w <- new_w / sum(new_w)
            errs[b,j] <- sum((t(X1) - 
                t(ctrls)%*% new_w)^2)


        }
    }
    ## get the hyperparameter with the best balance and refit
    best_lam <- hyperparams[which.min(apply(errs, 2, sum))]
    return(best_lam)
}
