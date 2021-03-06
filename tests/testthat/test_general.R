context("Generally testing the workflow")


test_that("No errors in fitting a one outcome model", {

    run_one <- function() {
        set.seed(12345)
        ## simulate data
        mo <- sim_factor_model(50, 50, 40, 10, 1)
        ## fit synthetic controls for one outcome
        out <- get_entropy(mo$outcomes %>% filter(outcome_id == 1),
                              mo$metadata, eps=100)
    }
    expect_error(run_one(), NA)
    })

test_that("No errors in fitting a multi outcome model", {

    run_multi <- function() {
        set.seed(12345)
        ## simulate data
        mo <- sim_factor_model(50, 50, 40, 10, 1)
        ## fit synthetic controls for one outcome
        out <- get_entropy(mo$outcomes,
                           mo$metadata,
                           eps=100,
                           outcome_col="outcome_id")
    }
    expect_error(run_multi(), NA)
    })

test_that("get_entropy says when problem is infeasible", {

    set.seed(12345)
    ## simulate data
    mo <- sim_factor_model(10, 50, 40, 10, 1)
    ## fit synthetic controls for one outcome
    out <- get_entropy(mo$outcomes,
                       mo$metadata,
                       eps=0,
                       outcome_col="outcome_id")
  
    expect_true(!out$feasible)
    })
