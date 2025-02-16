# Setup Guide for Running and Building the Repository with Terraform

This guide provides step-by-step instructions to set up, build, and deploy the repository using Terraform on both macOS and Linux systems. The deployment process is integrated with GitHub Actions: when a developer pushes to the master branch, the pipeline will build the Docker container, push it to Amazon ECR, and deploy it to AWS ECS.

## Table of Contents

1. [Overview](#overview)  
2. [Prerequisites](#prerequisites)  
3. [Environment Setup](#environment-setup)  
   - [Install Terraform](#install-terraform)  
   - [Install AWS CLI](#install-aws-cli)  
   - [Install Docker](#install-docker)  
4. [Repository Setup](#repository-setup)  
5. [Terraform Deployment](#terraform-deployment)  
6. [CI/CD Pipeline Overview](#cicd-pipeline-overview)  
7. [Deploying the Service](#deploying-the-service)  
8. [Troubleshooting](#troubleshooting)

## Overview

This repository includes:
- Terraform configurations to provision AWS resources such as ECS clusters, ECR repositories, VPCs, subnets, ALB, security groups, IAM roles, etc.
- GitHub Actions workflow that automates the following:
	- Checkout of the repository.
	- Configuration of AWS credentials.
	- Docker build, tag, and push to Amazon ECR.
	- ECS task definition update and ECS service deployment.

When a developer pushes code to the master branch, GitHub Actions is triggered, and the new Docker container is deployed to AWS.

## Prerequisites

Before setting up the repo, ensure you have the following installed on your system:
- Git: Version control system for cloning and managing the repository.
- Terraform: Infrastructure as Code (IaC) tool to manage AWS resources.
- AWS CLI: Command-line tool to interact with AWS.
- Docker: For building and running containerized applications.
- jq: Command-line JSON processor (used in deployment scripts).

Note: Instructions provided here apply to both macOS and Linux systems.

## Environment Setup

### Install Terraform

#### macOS

Using Homebrew:
```sh
brew tap hashicorp/tap  
brew install hashicorp/tap/terraform
```
#### Linux
1. Download the latest Terraform package from Terraform Downloads.
2. Unzip the package:
```sh
unzip terraform_<VERSION>_linux_amd64.zip
```
3. Move the executable to a directory included in your PATH:

```sh
sudo mv terraform /usr/local/bin/
```


Verify installation:
```sh
terraform -v
```

### Install AWS CLI

#### macOS

Using Homebrew:

```sh
brew install awscli
```

#### Linux

Download and install using the bundled installer:
```sh
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"  
unzip awscliv2.zip  
sudo ./aws/install
```

Verify installation:
```sh
aws --version
```
### Install Docker

Follow the official installation guides for Docker Desktop on macOS and Docker Engine on Linux.

## Repository Setup

1. Clone the repository:
```sh
git clone https://github.com/ChristopherHarwell/quest  
cd quest
```

2. Configure AWS Credentials:  

Set up your AWS credentials either by using the AWS CLI (aws configure) or by exporting the following environment variables:

```sh
export AWS_ACCESS_KEY_ID=<your_access_key_id>  
export AWS_SECRET_ACCESS_KEY=<your_secret_access_key>  
export AWS_DEFAULT_REGION=<your_preferred_region>
```

3. Install jq (if not already installed):

**macOS:**
```sh
brew install jq
```

**Linux (Debian/Ubuntu):**
```sh
sudo apt-get update && sudo apt-get install jq -y
```
## Terraform Deployment

### Follow these steps to deploy the AWS infrastructure:
1. Initialize Terraform:
```sh
terraform init
```

2. Review the Terraform Plan:  
This will show the resources that will be created.
```sh
terraform plan
```

3. Apply the Terraform Configuration: 
Confirm the changes and apply:
```sh
terraform apply
```

Type `yes` when prompted to proceed.

4. Verify Outputs:  
- After a successful apply, Terraform will output key information such as the ALB DNS name and the ECR repository URL. Use these outputs to verify that the infrastructure is properly set up.

## CI/CD Pipeline Overview

### GitHub Actions Workflow: 
On every push to the master branch, GitHub Actions will:
	1. Checkout the repository.
	2. Configure AWS credentials using provided secrets.
	3. Log in to Amazon ECR.
	4. Build, tag, and push the Docker image to ECR.
	5. Update the ECS task definition and deploy the ECS service.

#### Deployment Trigger: 
A push to the master branch automatically triggers the deployment pipeline, ensuring that the latest code is built and deployed to AWS ECS.

## Deploying the Service
### To deploy the service:
1. Commit and Push to Master:  

When you’re ready to deploy, commit your changes and push them to the master branch:
```sh
git add .  
git commit -m "Deploy: Update service with new changes"  
git push origin master
```

1. GitHub Actions Deployment:  
    Once the push is detected:
    - The CI/CD pipeline is triggered.
    - The Docker image is built and pushed to ECR.
    - The ECS service is updated with the new task definition.  

Monitor the GitHub Actions logs to ensure the deployment completes successfully.

## Troubleshooting
### Terraform Issues:  
If you encounter errors during terraform apply, review the error messages for missing configurations or permissions. Ensure that your AWS credentials are set correctly.

### GitHub Actions Failures:  
Check the logs in the GitHub Actions interface for any step that fails. Common issues include incorrect AWS credentials or problems with the Docker build process.

### AWS Resource Verification:  
Use the AWS Management Console to verify that ECS, ECR, and other resources are created and updated as expected.

## Summary
By following this guide, you can set up, build, and deploy the repository using Terraform. The automated CI/CD process will ensure that any push to the master branch results in a new deployment of the Docker container to ECS and ECR. Enjoy a seamless deployment experience!