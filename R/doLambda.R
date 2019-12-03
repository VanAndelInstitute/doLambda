#
# Inspiration drawn from doRedis (Bryan W. Lewis), which in turn drew
# inspiration from doMPI (Steve Weston)
#

.doLambdaGlobals <- new.env(parent=emptyenv())

#' registerDoLambda
#'
#' Tell doPar to use this backend
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

enqueue <- function(jobid) {}

dequeue <- function(jobid) {}


# internal. all the magic.
.doLambda <- function() {
  if (!inherits(obj, "foreach"))
    stop("obj must be a foreach object")
  it <- iter(obj)
  argsList <- .to.list(it)

  # create environment

  # job to S3
}
