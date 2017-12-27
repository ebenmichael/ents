% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/format.R
\name{format_data}
\alias{format_data}
\title{Format "long" panel data into "wide" matrices to fit synthetic controls}
\usage{
format_data(outcomes, metadata, trt_unit = 1, outcome_col = NULL)
}
\arguments{
\item{outcomes}{Tidy dataframe with the outcomes and meta data}

\item{metadata}{Dataframe of metadata}

\item{trt_unit}{Unit that is treated (target for regression), default: 0}

\item{outcome_col}{Column name which identifies outcomes,
if NULL then only one outcome is assumed}
}
\value{
List of data to use as an argument for Synth::synth,
        whether the unit was actually treated
}
\description{
Format "long" panel data into "wide" matrices to fit synthetic controls
}