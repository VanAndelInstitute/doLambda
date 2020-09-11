# doLambda

AWS Lambda as a backend for R's doParallel / foreach toolchain.

## Overview

### Background

The `foreach` and `doParallel` packages provide a convenient and uniform system 
for parallelizing computation. There are a number of backend implementations 
for `doParallel`, including `doMC`, `doSNOW`, `doFuture`, `doRedis`. These 
approaches are designed for server environments (including distributed server 
environments). 

Our own computational needs are highly intermittent, with long periods of 
quiescence puncuated by short periods of needs for "massive" scale. 
AWS lambda is an excellent solution for such use cases as it is transparently 
scalable, serverless, and has no associated costs when not in use. With the 
introduction of "bring your own runtime" in 2018, it is now possible to use 
R as the run time for lambda jobs.

A lambda backend for `doParallel` would make the barrier for entry for this 
architecture very low. In addition to familiarity with the foreach library, 
all that is required are AWS credentials, an S3 bucket to hold the job queue,
and a lambda application created with the runtime layers we provide.

### __Caveat Emptor__

This package is pre-alpha. It seems to work for simple tasks, and it may work 
for complex tasks. But I make no warranty, expressed or implied, that this 
software is suitable for any purpose. By using this software, you indicate 
that you understand the following warnings and caveats.

1. **If you create a race condition with AWS Lambda, you can unwittingly rack up 
large charges**. Take care not to run code that creates objects in the S3 bucket 
you specify as your job queue. And keep an eye on your lambda dashboard.

2. The lambda execution environment does not have an C compiler, 
so you cannot compile at runtime. That is to say, Rcpp is not supported at this 
time, although with the addition of another lambda layer containing the gcc 
toolchain, it should be possible to do. (Assuming that toolchain can be kept 
small enough to stay under the AWS Lambda size limits.)

### Web Console Vs. AWS CLI

The Lambda runtime and function needed by doLamda can be setup entirely through
the GUI provided by the AWS Web Console. However, for ease of documentation,
automation, and repeatability we use the AWS Command Line Interface (CLI) below
to perform the necessary AWS tasks (with the exception of initially creating the
requisite IAM user). But the choice is yours.

To use the AWS CLI, you will first need to run `aws configure` to set your AWS 
credentials (`key` and `secret` for the IAM User that has the necessary permissions 
(described below). Even if you use the AWS Web Console to set up your Lambda
function, you may still wish to run `aws configure` so you don't need to provide 
your credentials every time you use doLambda (which would not only be a pain 
but could be a security risk if you, for example, accidentally push your 
credentials to github).

### Setup Steps

To use AWS Lambda as a backend for doParallel, you will need to setup 
the R runtime environment on Lambda. Doing so requires three steps.

1. Create both an AWS IAM User and Role identities with the necessary
   permissions and provide the corresponding credentials.
2. Upload the R Runtime Layers and doLambda worker function to Lambda.
3. Create an S3 bucket for the job queue and set the Lambda trigger on that bucket.

The following sections provide further details on these steps. Note that 
additional details about setting up the R runtime for Lambda, including 
specific instructions on how to build these layers yourself, are provided at the 
[lambdar github repository](https://github.com/vanandelinstitute/lambdar). 

## IAM Identities and Permissions

### IAM User

You will need AWS credentials for an [IAM
user](https://console.aws.amazon.com/iam/home#/users) that has read/write
permissions on S3, can push lambda layers, and can execute lambda functions. You
will need the AWS Secret and Key that are created when creating the user
(alternatively, you can create new keys for that user if they go missing).
Presumably you can do all of this as the root user of your AWS account. That
would be fine for experimentation but is not best practice in production. The
credentials you provide must be for an IAM user that has the following
permissions:

* arn:aws:iam::aws:policy/AWSLambdaFullAccess
* arn:aws:iam::aws:policy/AmazonS3FullAccess
* arn:aws:iam::aws:policy/IAMFullAccess

(Actually you can be more granular than that. Feel free to tune the permissions
to fit your precise situation.)

### IAM Role

In addition to the IAM User--which you will need to create layers and functions--
you also will need to define an IAM Role for the functions to run under. 
This role gives your functions permissions to access AWS resources since the 
functions are not be executed by you (or your IAM User), but by the Lambda 
service. Thus, permissions must be granted to the function and this is done 
by means of a role, not a user.

First create a file named `trust_policy.json` with these contents:

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Then run this command to create the role (which here we call `Lambda-R-Role`):

```
aws iam create-role \
  --role-name doLambda-R-Role \
  --assume-role-policy-document file://trust_policy.json
```

Take a note of the ARN (Amazon Resource Name) returned by this command as you
will need it later (you can always look it up again on the web console). We then
need to add permissions to this role to work with Lambda functions and access
S3.

```
aws iam attach-role-policy \
    --role-name doLambda-R-Role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam attach-role-policy \
    --role-name doLambda-R-Role \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### Setting Credentials

The simplest way to set your AWS credentials (`key` and `secret` for the IAM
User that has the necessary permissions described above) such that doLambda can
find them is to run `aws configure` from the command line as mentioned above. 

If you cannot take this approach or do not want to, you can alternatively
provide your credentials directly to the call to `registerDoLambda`, or you can
set the corresponding environment variables. For example, from an R session.

```
Sys.setenv("AWS_ACCESS_KEY_ID" = "mykey",
           "AWS_SECRET_ACCESS_KEY" = "mysecretkey",
           "AWS_DEFAULT_REGION" = "us-east-1")
```

(Make sure you designate your default region, as failure to do so will cause the
AWS API calls to fail in subtle and crytpic ways.)

## Upload R Runtime Layers

You will need to upload the R runtime layers to AWS to run R scripts as 
lambda functions. Prebuilt layers--as well as instructions for building these 
layers from scratch--are availble from the 
[lambdar github repository](https://github.com/vanandelinstitute/lambdar). 
Each layer needs to be <50M zipped, so there are three layers:

* [subsystem.zip](https://github.com/VanAndelInstitute/lambdaR/raw/master/layers/subsystem.zip)
* [r.zip](https://github.com/VanAndelInstitute/lambdaR/raw/master/layers/r.zip)
* [r_lib.zip](https://github.com/VanAndelInstitute/lambdaR/raw/master/layers/r_lib.zip)

You can then push these layers up to AWS. Take note of the ARN (Amazon Resource Name) 
returned for each as you will need them later (you can always look them up again 
through the Lambda web console).

```
aws lambda publish-layer-version --layer-name subsystem --zip-file fileb://subsystem.zip
aws lambda publish-layer-version --layer-name R --zip-file fileb://r.zip
aws lambda publish-layer-version --layer-name r_lib --zip-file fileb://r_lib.zip
```

## Create the worker function

The worker script is provided by the doLambda library. You can either [download it 
from github](https://github.com/VanAndelInstitute/doLambda/raw/master/inst/R/worker.R) 
or find it on your system by running this from an R session:

```
paste0(system.file("R", package = "doLambda"), "/worker.R")
```

**TO DO**: I should provide the zipped worker script in the repo or include it
in the runtime layer (?).

Zip this file and upload it to Lambda as follows (adjusting the path to worker.R if necessary).
Note that you will need to replace the role and layers ARNs specified below for the one for the 
role you created earlier. Note also the timeout is set to 30 seconds in the example below. The 
timeout should be at least 4 seconds to give time for the subsystem to initialize and the runtime 
to load. However, longer timeouts may be required if your parallelized function is computationally 
intensive.

```
wget https://github.com/VanAndelInstitute/doLambda/raw/master/inst/R/worker.R
mv worker.R worker.r
zip worker.zip worker.r
aws lambda create-function \
    --function-name dolambda \
    --layers "arn:aws:lambda:us-east-1:436870896339:layer:R:1" "arn:aws:lambda:us-east-1:436870896339:layer:r_lib:1" "arn:aws:lambda:us-east-1:436870896339:layer:subsystem:1" \
    --runtime provided \
    --timeout 30 \
    --zip-file fileb://worker.zip \
    --handler worker.handler \
    --role arn:aws:iam::436870896339:role/doLambda-R-Role
```

## Set Up S3 Queue Bucket

The last step is to create an S3 bucket where our jobs will be stored and create
a trigger such that our doLambda worker function gets called whenever a job is
uploaded to this bucket by doLambda. Note that you will need to pick a different
bucket name then showed below as S3 bucket names must be unique accross all AWS
users. Make sure this bucket is in the same region as your lambda function.

```
aws s3api create-bucket --bucket do-lambda-4 \
  --region us-east-1 

```

We can then add a trigger to our S3 bucket. Save the following in a file called
`s3_trigger.json`. You will need to substitute the actual ARN for the lambda
function you created above. 

```
{
"LambdaFunctionConfigurations": [
    {
      "Id": "doLambdaTrigger",
      "LambdaFunctionArn": "arn:aws:lambda:us-east-1:436870896339:function:doLambda",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": "rds"
            },
            {
              "Name": "prefix",
              "Value": "jobs/"
            }
          ]
        }
      }
    }
  ]
}
```

Before we can apply this trigger our S3 bucket must be given permission to
trigger lambda functions.

```
aws lambda add-permission \
  --function-name dolambda \
  --action lambda:InvokeFunction \
  --statement-id s3 \
  --principal s3.amazonaws.com \
  --output text
```

And then we can apply the trigger to our bucket. Again, substitute the actual
name of the bucket you created.

```
aws s3api put-bucket-notification-configuration \
  --bucket  do-lambda-4 \
  --notification-configuration file://s3_trigger.json 
```

## Try Me

That's it. You should be able to install the doLambda R library on any machine
(if you haven't already), and give it a try. 
