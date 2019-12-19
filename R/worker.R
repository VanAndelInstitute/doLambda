#' lambdaWorker
#'
#' Retrieve job and execute it.
#'
#' @param bucket name of an S3 bucket you own that will hold the job queue
#' @param key AWS Access Key. 
#' 
#' @note This function is automatically called (by the boostrap script) when the 
#' lambda job is triggered. It typically is never used on the client end. It is
#' assumed that the lambda function is executed by a role that has read and write
#' permissions for the specified S3 bucket.
#'
#' @return nothing. Called for side effect of doing a unit of work.
#' @importFrom aws.s3 s3readRDS s3saveRDS
#' @export
lambdaWorker <- function(bucket, key) {
  dat <- s3readRDS(key, bucket)  
  res <- eval(dat$expr, dat$envir, dat$enclos)
  key <- gsub("jobs/", "outs/", key)
  s3saveRDS(res, key, bucket)  
}

# call lambdaWorker if this script was sourced directly 
# (as is done by our lambda bootstrap script)
if(exists("args") && length(args) == 2) {
  library(doLambda)
  lambdaWorker(args[1], args[2])  
}