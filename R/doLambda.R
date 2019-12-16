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
#' 
#' @note If credentials are not provided (key, secret, and region), asw,signature 
#' will be used to locate them by searching in the following order: environment 
#' variables (`AWS_ACCESS_KEY`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION`),
#' ./.aws/credentials, and finally ~/.aws/credentials. If no credentials can be 
#' found, the function will throw an error.
#'
#' @return nothing. Called for side effect of registering doParallel backend.
#' @importFrom foreach foreach %do%
#' @importFrom iterators iter
#' @export
registerDoLambda <- function(bucket,
                             key=NULL,
                             secret=NULL,
                             region=NULL)
{
  cred <- list()
  cred$key <- ifelse(!is.null(key),
                     key,
                     aws.signature::locate_credentials()$key)
  if(!!nchar(cred$key))
    stop("No AWS credentials provided.")
  
  cred$secret <- ifelse(!is.null(secret),
                        secret,
                        aws.signature::locate_credentials()$secret)
  if(!!nchar(cred$key))
    stop("No AWS credentials provided.")
  
  cred$region <- ifelse(!is.null(region),
                        region,
                        aws.signature::locate_credentials()$region)
  if(!!nchar(cred$key))
    stop("No AWS credentials provided.")
  
  assign("credentials", cred, envir = .doLambdaOptions)
  if(!aws.s3::bucket_exists(bucket)) 
    aws.s3::put_bucket(buckey, cred$region)
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

lambdaExec <- function(path, bucket) {
  # load obj from S3
  obj <- aws.s3::s3readRDS(path, bucket)
  expr <- obj$expr
  envir <- obj$envir
  enclos <- obj$enclos
  arg <- obj$arg
  c.expr <- compiler::compile(expr, env=envir, options=list(suppressUndefined=TRUE))
  res <- eval(c.expr, envir=arg, enclos = enclos)
  # write result to S3
  # remove job from S3
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
                 envir = envir,
                 enclos = exportenv,
                 arg = a)
    aws.s3::s3saveRDS(obj, paste0(stackid, job, ".rds"), bucket)
    job <- job + 1
  }
  totjobs <- job - 1
  
  # poll for job completion...
  complete <- 0
  while(complete < totjobs) {
    # count files in out
    # update progress bar if applicable
  }
  
  # fetch results
  job <- 1
  results <- foreach(a=argsList) %do% {
    res <- aws.s3::s3readRDS(paste0(stackid, "/outs/", jobid, job, ".rds"), bucket)
    job <- job + 1
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
  
  # don't export explicitly blacklisted variables, nor the iterator variable
  noexport <- union(obj$noexport, obj$argnames)
  
  # load everything else from calling environment into our new environment 
  getexports(expr, exportenv, envir, good=ls(envir), bad=noexport)
  
  # load requested objects from outside the calling environment
  export <- unique(obj$export)
  ignore <- intersect(export, vars)
  export <- setdiff(export, ignore)
  for (sym in export) {
    if (!exists(sym, envir, inherits=TRUE))
      stop(sprintf('unable to find variable "%s"', sym))
    val <- get(sym, envir, inherits=TRUE)
    if (is.function(val) &&
        (identical(environment(val), .GlobalEnv) ||
         identical(environment(val), envir))) {
      environment(val) <- exportenv
    }
    assign(sym, val, pos=exportenv, inherits=FALSE)
  }
  exportenv
}