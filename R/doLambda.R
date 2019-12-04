#   Copyright 2019 Eric J. Kort
#
#   Permission is hereby granted, free of charge, to any person obtaining a copy
#   of this software and associated documentation files (the "Software"), to
#   deal in the Software without restriction, including without limitation the
#   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
#   sell copies of the Software, and to permit persons to whom the Software is
#   furnished to do so, subject to the following conditions:
#
#   The above copyright notice and this permission notice shall be included in
#   all copies or substantial portions of the Software.
#  
#   This code was adapted from the doRedis package by B. W. Lewis.
#
#   The environment initialization code is adapted (with minor changes)
#   from the doMPI package from Steve Weston.
#   

#' registerDoLambda
#'
#' Tell doPar to use this backend.
#'
#' @param bucket name of an S3 bucket you own that will hold the job queue
#' @param key AWS Access Key. If not provided, will be retrieved from
#'            AWS_ACCESS_KEY_ID environment variable.
#' @param secret AWS Secret Key. If not provided, will be retrieved from
#'            AWS_SECRET_ACCESS_KEY environment variable.
#' @param region AWS Default Region. If not provided, will be retrieved from
#'            AWS_DEFAULT_REGION environment variable.
#'
#' @return nothing. Called for side effect of registering doParallel backend.
#' @importFrom foreach foreach %do%
#' @importFrom jsonlite fromJSON
#' @importFrom RCurl getForm
#' @export
#
# TO DO: Does running aws configure eliminate the need to specify credentials?
#
registerDoLambda <- function(bucket,
                             key=NULL,
                             secret=NULL,
                             region=NULL)
{
  cred <- list()
  cred$key <- ifelse(!is.null(key),
                     key,
                     Sys.getenv("AWS_ACCESS_KEY_ID"))
  if(!!nchar(cred$key))
    stop("No AWS credentials provided.")

  cred$secret <- ifelse(!is.null(secret),
                     secret,
                     Sys.getenv("AWS_SECRET_ACCESS_KEY"))
  if(!!nchar(cred$key))
    stop("No AWS credentials provided.")

  cred$region <- ifelse(!is.null(region),
                     region,
                     Sys.getenv("AWS_DEFAULT_REGION"))
  if(!!nchar(cred$key))
    stop("No AWS credentials provided.")

  assign("credentials", cred, envir = .doLambdaGlobals)

  setDoPar(fun = .doLambda,
           data = list(bucket = bucket),
           info = .info)
  invisible()
}

# Internal. A foreach requirement.
.info <- function(data, item)
{
  switch(item,
         workers= 1, # a bald faced lie. will come back to it.
         name="doLambda",
         version=packageDescription("doLambda", fields="Version"),
         NULL)
}

#' removeQueue
#' 
#' Remove queue from S3 bucket.
#' 
#' @param queue the doRedis queue name
#'
#' @note Workers listening for work on more than one queue will only
#' terminate after all their queues have been deleted.
#'
#' @return
#' NULL is invisibly returned.
#'
#' @import rredis
#' @export
removeQueue <- function(queue)
{
  invisible()
}

# internal
.makeDotsEnv <- function(...)
{
  list(...)
  function() NULL
}

# internal. all the magic.
#
# TODO: what is data?
#
#' @importFrom aws.s3 save_object
.doLambda <- function(obj, expr, envir, data) {
  if (!inherits(obj, "foreach"))
    stop("obj must be a foreach object")
  it <- iter(obj)
  argsList <- .to.list(it)
  
  ID <- basename(tempfile(pattern = ""))
  # tempfile can produce the same name if used in multiple threads; adding PID avoids this problem
  ID <- paste(Sys.getpid(), ID, sep = "")
  
  # ID from doRedis is fortified with user name and time, but I do not (yet) see the 
  # need for that in this context (other than possibly debugging)
  # ID <- paste( ID, Sys.info()["user"], Sys.info()["nodename"], Sys.time(), sep="_")
  # ID <- gsub(" ", "-", ID)  
  
  queue <- data$bucket
  queueEnv <- paste("env", ID, sep=".")
  queueOut <- paste("out", ID, sep=".")
  queueStart <- paste("start", ID, sep=".")
  queueStart <- paste(queueStart, "*", sep="")
  queueAlive <- paste(queue,"alive", ID, sep=".")
  queueAlive <- paste(queueAlive, "*", sep="")
  
  if (!inherits(obj, "foreach"))
    stop("obj must be a foreach object")
  
  gather <- it$combineInfo$fun
  
  exportenv <- .init_env()
  
  # save queue environment to S3
  aws.s3::s3saveRDS(exportenv, queueEnv, queue)
  
}

.init_env <- function() {
  # Verbatim from doRedis and nearly verbatim from doMPI
  
  # Setup the parent environment by first attempting to create an environment
  # that has '...' defined in it with the appropriate values
  exportenv <- tryCatch({
    qargs <- quote(list(...))
    args <- eval(qargs, envir)
    environment(do.call(.makeDotsEnv, args))
  },
  error=function(e) {
    new.env(parent=emptyenv())
  })
  noexport <- union(obj$noexport, obj$argnames)
  getexports(expr, exportenv, envir, bad=noexport)
  vars <- ls(exportenv)
  if (obj$verbose) {
    if (length(vars) > 0) {
      cat("automatically exporting the following objects",
          "from the local environment:\n")
      cat(" ", paste(vars, collapse=", "), "\n")
    } else {
      cat("no objects are automatically exported\n")
    }
  }
  # Compute list of variables to export
  export <- unique(c(obj$export, .doRedisGlobals$export))
  ignore <- intersect(export, vars)
  if (length(ignore) > 0) {
    warning(sprintf("already exporting objects(s): %s",
                    paste(ignore, collapse=", ")))
    export <- setdiff(export, ignore)
  }
  # Add explicitly exported variables to exportenv
  if (length(export) > 0) {
    if (obj$verbose)
      cat(sprintf("explicitly exporting objects(s): %s\n",
                  paste(export, collapse=", ")))
    for (sym in export) {
      if (!exists(sym, envir, inherits=TRUE))
        stop(sprintf("unable to find variable \"%s\"", sym))
      assign(sym, get(sym, envir, inherits=TRUE),
             pos=exportenv, inherits=FALSE)
    }
  }
  exportenv
}

## unimplemented functions follow. 
## where applicable, might implement in the future

# note that once the lambda functions are triggered, you can't 
# stop them. So queue removal may not serve any useful purpose.
removeQueue <- function(queue) { invisible() }

setExport <- function() { invisible() }
setPackages <- function() { invisible() }
setProgress <- function() { invisible() }
setFtinterval <- function(value=30){ invisible() }
setChunkSize <- function(value=1){ invisible() }

# we will do all our reducing locally. could use another lambda
# function to perform intermediate reduction in the future.
setReduce <- function(fun=NULL){ 
  if(!is.null(fun)) {
    message("Reduce function passed, but not supported. Using .combine instead.")
  }
  return(assign("gather", TRUE, envir=.doRedisGlobals)) 
}