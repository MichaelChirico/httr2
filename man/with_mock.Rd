% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/req-mock.R
\name{with_mock}
\alias{with_mock}
\alias{local_mock}
\title{Temporarily mock requests}
\usage{
with_mock(mock, code)

local_mock(mock, env = caller_env())
}
\arguments{
\item{mock}{A single argument function called with a request object.
It should return either \code{NULL} (if it doesn't want to handle the request)
or a \link{response} (if it does).}

\item{code}{Code to execute in the temporary environment.}

\item{env}{Environment to use for scoping changes.}
}
\value{
\code{with_mock()} returns the result of evaluating \code{code}.
}
\description{
Mocking allows you to selectively and temporarily replace the response
you would typically receive from a request with your own code. It's
primarily used for testing.
}
\examples{
# This function should perform a response against google.com:
google <- function() {
  request("http://google.com") \%>\%
    req_perform()
}

# But I can use a mock to instead return my own made up response:
my_mock <- function(req) {
  response(status_code = 403)
}
with_mock(my_mock, google())
}
