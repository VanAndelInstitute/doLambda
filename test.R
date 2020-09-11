library(foreach)
library(Rcpp)

doLambda::registerDoLambda(bucket = "do-lambda-4")

b <- 12

res <- foreach(i=1:10) %dopar% {
  i * 3 * b
}
