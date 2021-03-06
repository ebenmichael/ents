% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/multiple_outcomes.R
\name{get_separate}
\alias{get_separate}
\title{Fit synthetic controls for multiple outcomes separately}
\usage{
get_separate(outcomes, metadata, syn_func, name, trt_unit = 1)
}
\arguments{
\item{outcomes}{Tidy dataframe with the outcomes and meta data}

\item{metadata}{Dataframe of metadata}

\item{syn_func}{Function to get synthetic controls}

\item{name}{Name of the synthetic control method}

\item{trt_unit}{Unit that is treated (target for regression), default: 0}
}
\value{
both outcomes with additional synthetic controls added
        weights for both synthetic controls
}
\description{
Fit synthetic controls for multiple outcomes separately
}
