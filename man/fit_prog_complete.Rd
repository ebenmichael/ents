% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/highdim.R
\name{fit_prog_complete}
\alias{fit_prog_complete}
\title{Use nuclear norm matrix completion to fit outcome model}
\usage{
fit_prog_complete(X, y, trt, rank.max = 5, lambda = 0, type = "svd")
}
\arguments{
\item{X}{Matrix of covariates/lagged outcomes}

\item{y}{Matrix of post-period outcomes}

\item{trt}{Vector of treatment indicator}

\item{rank.max}{Max rank of the solution}

\item{type}{"svd" is soft-thresholded SVD and "als" is alternating ridge}

\item{lambdaNuclear}{norm regularization parameter}
}
\value{
\itemize{
          \item{y0hat }{Predicted outcome under control}
          \item{params }{Regression parameters}}
}
\description{
Use nuclear norm matrix completion to fit outcome model
}
