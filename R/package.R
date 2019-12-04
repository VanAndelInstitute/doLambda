#' A Lambda parallel back end for foreach.
#'
#' The doLambda package implements a backend for using AWS lambda as
#' the backend, with S3 serving as the job queue.
#'
#' @name doLambda-package
#' 
#' @useDynLib doLambda
#' @seealso \code{\link{registerDoLambda}}
#' @docType package
NULL

.doLambdaGlobals <- new.env(parent=emptyenv())