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

#args = commandArgs(trailingOnly=TRUE)
#print(args)

id <- basename(tempfile(pattern=""))
ROOT <- Sys.getenv("AWS_LAMBDA_RUNTIME_API")
EVENT_DATA <- httr::GET(paste0("http://", ROOT, "/2018-06-01/runtime/invocation/next"))
REQUEST_ID <- EVENT_DATA$headers$`lambda-runtime-aws-request-id`

res <- httr::content(EVENT_DATA)
bucket <- res$Records[[1]]$s3$bucket$name
key <- res$Records[[1]]$s3$object$key
aws.s3::s3saveRDS(EVENT_DATA, paste0("eventdata_", id, "_", 1, ".rds"), "jlab-test-4")

httr::POST(paste0("http://", 
           ROOT, 
           "/2018-06-01/runtime/invocation/",
           REQUEST_ID, 
           "/response"),
           body = "OK")

#library(doLambda)
#library(aws.s3)
#lambdaWorker(args[1], args[2])  

# how do we know if we are done?
EVENT_DATA <- httr::GET(paste0("http://", ROOT, "/2018-06-01/runtime/invocation/next"))
aws.s3::s3saveRDS(EVENT_DATA, paste0("eventdata_", id, "_", 2, ".rds"), "jlab-test-4")
