# Sneaking this file into the R directory at installation as it gets 
# directly sourced by our lambda bootstrap function.
lambdaWorker <- function(bucket, key) {
  dat <- s3readRDS(key, bucket)  
  res <- eval(dat$expr, dat$envir, dat$enclos)
  key <- gsub("jobs/", "outs/", key)
  print("Saving res to ")
  print(paste0(bucket, "/", key))
  s3saveRDS(res, key, bucket)  
}

args = commandArgs(trailingOnly=TRUE)
print(args)

if(length(args) == 2) {
  library(doLambda)
  library(aws.s3)
  lambdaWorker(args[1], args[2])  
  print("done")
}