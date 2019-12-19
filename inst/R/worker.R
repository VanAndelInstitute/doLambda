library(aws.s3)

# Sneaking this file into the R directory at installation as it gets 
# directly sourced by our lambda bootstrap function.
lambdaWorker <- function(bucket, key) {
  print(paste0("Attempting to retrieve ", key, " from ", bucket))
  dat <- s3readRDS(key, bucket)  
  print(paste0("Done."))
  res <- eval(dat$expr, dat$envir, dat$enclos)
  key <- gsub("jobs/", "outs/", key)
  print("Saving res to ")
  print(paste0(bucket, "/", key))
  s3saveRDS(res, key, bucket)  
}

id <- basename(tempfile(pattern=""))
ROOT <- Sys.getenv("AWS_LAMBDA_RUNTIME_API")
EVENT_DATA <- httr::GET(paste0("http://", ROOT, "/2018-06-01/runtime/invocation/next"))
REQUEST_ID <- EVENT_DATA$headers$`lambda-runtime-aws-request-id`

res <- httr::content(EVENT_DATA)
bucket <- res$Records[[1]]$s3$bucket$name
key <- res$Records[[1]]$s3$object$key

print(paste0("Running job with key ", key, " in bucket ", bucket, "."))
lambdaWorker(bucket, key)  
print("Done.")

httr::POST(paste0("http://", 
                  ROOT, 
                  "/2018-06-01/runtime/invocation/",
                  REQUEST_ID, 
                  "/response"),
           body = "SUCCESS!", encode="form")
