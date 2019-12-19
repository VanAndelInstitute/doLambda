# Copyright 2019 Eric J. Kort. Code from doMC package Copyright (c) 2008-2010, 
# Revolution Analytics. Code from doMPI package Copyright (c) 2009--2013, 
# Stephen B. Weston.
#
# This program is free software; you can redistribute it and/or modify 
# it under the terms of the GNU General Public License (version 2) as 
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty of 
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
# General Public License for more details.
#
# A copy of the GNU General Public License is available at
# http://www.r-project.org/Licenses/
#
# This code was adapted from the doMC package by Rich Calaway, and the doMPI
# package by Stephen B. Weston, and many parts of it remain verbatim as they 
# appear in those packages.
#
.doLambdaOptions <- new.env(parent=emptyenv())

#' registerDoLambda
#'
#' Tell doPar to use this backend.
#'
#' @param bucket name of an S3 bucket you own that will hold the job queue
#' @param key AWS Access Key. 
#' @param secret AWS Secret Key. 
#' @param region AWS Default Region. 
#' @param throttle How long to pause between progress checks to play nice with 
#' AWS endpoints. Minimum is 2 seconds (default)
#' 
#' @note If credentials are not provided (key, secret, and region), asw,signature 
#' will be used to locate them by searching in the following order: environment 
#' variables (`AWS_ACCESS_KEY`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION`),
#' ./.aws/credentials, and finally ~/.aws/credentials. If no credentials can be 
#' found, the function will throw an error.
#'
#' @return nothing. Called for side effect of registering doParallel backend.
#' @importFrom foreach foreach %do% setDoPar
#' @importFrom iterators iter
#' @export
registerDoLambda <- function(bucket,
                             key=NULL,
                             secret=NULL,
                             region=NULL,
                             throttle = 2)
{
  throttle = max(throttle, 2)
  cred <- list()
  cred$key <- ifelse(!is.null(key),
                     key,
                     aws.signature::locate_credentials()$key)
  if(!nchar(cred$key))
    stop("No AWS credentials provided (key).")
  
  cred$secret <- ifelse(!is.null(secret),
                        secret,
                        aws.signature::locate_credentials()$secret)
  if(!nchar(cred$secret))
    stop("No AWS credentials provided (secret).")
  
  cred$region <- ifelse(!is.null(region),
                        region,
                        aws.signature::locate_credentials()$region)
  if(!nchar(cred$region))
    stop("No AWS credentials provided (region).")
  
  assign("credentials", cred, envir = .doLambdaOptions)
  assign("throttle", throttle, envir = .doLambdaOptions)
  if(!check_bucket(bucket)) 
    stop("Bucket not accessible and could not be created.")
  setDoPar(fun = doLambda,
           data = list(bucket = bucket),
           info = info)
}

# passed to setDoPar via registerDoLambda, and called by getDoParWorkers, etc
info <- function(data, item) {
  switch(item,
         workers=workers(data),
         name='doMC',
         version=packageDescription('doMC', fields='Version'),
         NULL)
}

getKey <- function() {
  .doLambdaOptions$credentials$key
}

getSecret <- function() {
  .doLambdaOptions$credentials$secret
}

getRegion <- function() {
  .doLambdaOptions$credentials$region
}

#
# convenience wrapper to inject credentials so 
# we don't need to perform credential lookup  
# every time we make an AWS call.
#
with_cred <- function(f, ...) {
  args <- list(...)
  args$key <- getKey()
  args$secret = getSecret()
  args$region = getRegion()
  do.call(f, args)
}


#
# See if bucket exists, and create it if not
# (if possible)
#' @export
check_bucket <- function(b) {
  res <- with_cred(aws.s3::s3HTTP, verb="HEAD", bucket=b)
  if(!res) {
    tryCatch({
      with_cred(aws.s3::put_bucket, b, location_constraint = getRegion())
      res <- TRUE
    }, error = function(e) {
      res <- FALSE
    })
  }
  res
}

idgen <- function() {
  time_ms <- paste0(round(as.numeric(Sys.time())*1000))
  paste(Sys.getpid(), 
                    basename(tempfile("")), 
                    time_ms, 
                    sep = "")
}

doLambda <- function(obj, expr, envir, data) {
  stackid <- idgen()
  
  if (!inherits(obj, 'foreach'))
    stop('obj must be a foreach object')
  exportenv <- .makeEnv(obj, expr, envir)
  it <- iter(obj)
  argsList <- as.list(it)
  accumulator <- makeAccum(it)
  # make sure all of the necessary libraries have been loaded
  for (p in obj$packages)
    library(p, character.only=TRUE)
  job <- 1
  for(a in argsList) {
    obj <- list( expr = expr, 
                 envir = a,
                 enclos = exportenv)
    with_cred(aws.s3::s3saveRDS,obj, 
                      paste0("jobs/", stackid, "_", job, ".rds"), 
                      data$bucket)
    job <- job + 1
  }
  totjobs <- job - 1
  
  # poll for job completion...
  complete <- 0
  incomplete <- 1:totjobs
  attempts <- 0
  while(complete < totjobs) {
    notdone <- NULL
    for(i in incomplete) {
      job <- paste0("outs/", stackid, "_", i, ".rds") 
      if(!suppressMessages(with_cred(aws.s3::object_exists,
                                     job,
                                     data$bucket))) {
        notdone <- c(notdone, i)
      } else {
        job <- gsub("^outs/", "jobs/", job)
        with_cred(aws.s3::delete_object, job, data$bucket)
        complete <- complete + 1
      }
    }
    incomplete <- notdone
    # update progress bar
    cat(paste0(complete, " out of ", totjobs, " jobs complete.\n"))
    # if(attempts>3) stop("Gave up after 3 attempts")
    attempts <- attempts + 1
    if(length(incomplete))
      Sys.sleep(.doLambdaOptions$throttle)
  }
  
  # fetch results
  job <- 1
  results <- foreach(i = 1:totjobs) %do% {
    res <- with_cred(aws.s3::s3readRDS, 
                     paste0("outs/", stackid, "_", i, ".rds"),
                     data$bucket)
    with_cred(aws.s3::delete_object, 
              paste0("outs/", stackid, "_", i, ".rds"), 
              data$bucket)
    res
  }
  accumulator(results, seq(along=results))
  
  errorValue <- getErrorValue(it)
  errorIndex <- getErrorIndex(it)
  
  # throw an error or return the combined results
  if (identical(obj$errorHandling, 'stop') && !is.null(errorValue)) {
    msg <- sprintf('task %d failed - "%s"', errorIndex,
                   conditionMessage(errorValue))
    stop(simpleError(msg, call=expr))
  } else {
    getResult(it)
  }
}

# internal
.makeDotsEnv <- function(...)
{
  list(...)
  function() NULL
}

# internal
.makeEnv <- function(obj, expr, envir) {
  # IF `...` exists in the calling environment, load its elements with 
  # their appropriate names and return that environment
  exportenv <- tryCatch({
    qargs <- quote(list(...))
    args <- eval(qargs, envir)
    environment(do.call(.makeDotsEnv, args)) 
  },
  # otherwise we create a new environment from scratch
  error=function(e) {
    new.env(parent=emptyenv())
  })
  vars <- ls(exportenv)
  
  # don't export explicitly blacklisted variables, nor the iterator variable
  noexport <- union(obj$noexport, obj$argnames)
  
  # load everything else from calling environment into our new environment 

  export <- expandsyms(getsyms(expr), good=character(0), bad=character(0), envir)
  export <- unique(c(obj$export, export))
  ignore <- intersect(export, vars)
  export <- setdiff(export, ignore)
  getexports(expr, exportenv, envir, good=export, bad=noexport)
  parent.env(exportenv) <- .GlobalEnv
  exportenv
}