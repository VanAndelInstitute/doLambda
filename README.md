# doLambda

AWS Lambda as a backend for R's doParallel / foreach toolchain.

## Background

The `foreach` and `doParallel` packages provide a convenient and uniform system 
for parallelizing computation. There are a number of backend implementations 
for `doParallel`, including `doMC`, `doSNOW`, `doFuture`, `doRedis`. These 
approaches are designed for server environments (including distributed server 
environments). 

Our own computational needs are highly intermittent, with long periods of 
quiescence puncuated by short periods of needs for massive scale. 
AWS lambda is an excellent solution for such use cases as it is transparently 
scalable, serverless, and has no associated costs when not in use. With the 
introduction of "bring your own runtime" in 2018, it is now possible to use 
R as the run time for lambda jobs.

A lambda backend for `doParallel` would make the barrier for entry for this 
architecture very low. In addition to familiarity with the foreach library, 
all that is required are AWS credentials, an S3 bucket to hold the job queue,
and a lambda application created with the runtime layers we (will) provide.

## Pre-requisites

You will need AWS credentials for a user or role that has read/write permissions
on S3 and can execute lambda functions. You can provide these credentials either 
directly to the call to `registerDoLambda`, but a better way is do set the 
corresponding environment variables. For example, from an R session:

```
Sys.setenv("AWS_ACCESS_KEY_ID" = "mykey",
           "AWS_SECRET_ACCESS_KEY" = "mysecretkey",
           "AWS_DEFAULT_REGION" = "us-east-1")
```

Make sure you designate your default region (even though S3 is regionless), as 
failure to do so will cause the AWS API calls to fail in subtle and crytpic 
ways.

You will also need a lambda application defined with the R runtime and the 
job retrieval/executing script provided by this package. This application must 
be configured to execute upon changes to the S3 bucket you designate as the 
job queue when calling `registerDoLambda`. This is all easier than it sounds 
and better documentation will appear here shortly.

