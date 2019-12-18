#' lambdaWorker
#'
#' Retrieve job and execute it.
#'
#' @note This function is automatically called (by the boostrap script) when the 
#' lambda job is triggered. It typically is never used on the client end. 
#'
#' @return nothing. Called for side effect of doing a unit of work.
#' @importFrom aws.s3 s3readRDS s3saveRDS
#' @export
lambdaWorker <- function() {
  root <- Sys.getenv("AWS_LAMBDA_RUNTIME_API")
  url <- paste0("http://", root, "/2018-06-01/runtime/invocation/next")
  res <- GET(url)
  payload <- content(res)
  
  key <- payload$Records[[1]]$s3$object$key
  bucket <- payload$Records[[1]]$s3$bucket$name
  dat <- s3readRDS(key, bucket)  

  res <- eval(dat$expr, dat$envir, dat$enclos)
  key <- gsub("jobs/", "outs/", key)
  s3saveRDS(res, key, bucket)  
}