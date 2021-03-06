% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/inference.R
\name{est_att}
\alias{est_att}
\title{Fit weights and get att estimates}
\usage{
est_att(metadata, fitfunc, trt_unit)
}
\arguments{
\item{metadata}{with treatment time}

\item{fitfunc}{Partially applied fitting function which takes in
the number of the treated unit}

\item{trt_unit}{Number of the treated unit}
}
\value{
Dataframe with ATT estimates
}
\description{
Fit weights and get att estimates
}
