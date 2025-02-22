# Technical Reference Document

## Table of Contents

1. [Overview](#overview)  
2. [Approach Taken](#approach-taken)  
   - [2.1 Description of the Implemented Architecture](#21-description-of-the-implemented-architecture)  
   - [2.2 Justification for the Approach Taken](#22-justification-for-the-approach-taken)  
3. [The Ideal Approach (If Using AWS Lambda)](#the-ideal-approach-if-using-aws-lambda)  
   - [3.1 Why This Was the Ideal Approach for AWS Lambda](#31-why-this-was-the-ideal-approach-for-aws-lambda)  
4. [Trade-offs and Challenges](#trade-offs-and-challenges)  
5. [Technical Documentation: Setting Up Terraform on AWS](#technical-documentation-setting-up-terraform-on-aws)  
   - [5.1 Initial Attempt: Lambda Function](#51-initial-attempt-lambda-function)  
   - [5.2 Building a Docker Container](#52-building-a-docker-container)  
     - [Corepack/Pnpm Error and Resolution](#corepackpnpm-error-and-resolution)  
     - [Final Dockerfile](#final-dockerfile)  
     - [Local Docker Build & Run Issues](#local-docker-build--run-issues)  
     - [Automation with a Shell Script](#automation-with-a-shell-script)  
   - [5.3 Pivot to ECS and ECR](#53-pivot-to-ecs-and-ecr)  
     - [GitHub Actions & AWS Credentials](#github-actions--aws-credentials)  
     - [ECR Registry (Private vs. Public) and ECS Pull Issues](#ecr-registry-private-vs-public-and-ecs-pull-issues)  
     - [Networking & Subnet Challenges](#networking--subnet-challenges)  
     - [CI/CD Pipeline Refinements](#cicd-pipeline-refinements)  
     - [IAM Roles: Task Execution Role vs. Task Role](#iam-roles-task-execution-role-vs-task-role)  
   - [5.4 Final Terraform Solution & Architecture Diagram](#54-final-terraform-solution--architecture-diagram)
     - [Encrypting SSL Certificates with SOPS & AGE](#encrypting-ssl-certificates-with-sops-age)
6. [Final Observations & Conclusion](#final-observations--conclusion)  
7. [References](#references)

---

## 1. Overview

This document provides a detailed explanation of the **approach taken** for deploying the **Quest Service** using AWS ECS (Elastic Container Service) with Fargate instead of AWS Lambda, as originally planned. It also explains how I set up my AWS infrastructure using Terraform. The document covers:
- The Docker build errors I faced (especially those involving Corepack and pnpm).
- The Terraform configuration challenges with networking, subnets, and ALB dependencies.
- How I debugged ECS tasks that couldn’t pull images from a private ECR registry.
- The adjustments I made to my CI/CD pipeline in GitHub Actions.
- The final ECS-based architecture along with the required IAM roles.
- Several Mermaid.js diagrams illustrating the complete architecture and the evolution of the design.

---

## 2. Approach Taken

### 2.1 Description of the Implemented Architecture

The chosen architecture uses **AWS ECS with Fargate**, **Elastic Load Balancer (ALB)**, **Elastic Container Registry (ECR)**, **CloudWatch Logs**, and **Terraform** for infrastructure provisioning. The key components are outlined in the Mermaid diagram below:

[![](https://mermaid.ink/img/pako:eNqNVV1v2jAU_SuWn2kFKVBg0iRKGUNqpypkq7QxRcYxIWqwM3-UstL_vmvHCdCWai9g-55z77XPsfOMqUgYHuBUkmKFoutPcz7nCCmzKFeG97N4ypeSKC0N1UYyG0box93o1xzDL_pjmNLxY0Hn-Dc6O_u8-0rUDk0n9xCfcs0kZxpNiGYbsvXgdAPYMg_gHCkURjOFIkmWy4zuUBgB3S2iiCxy5plS18wwcsSR4JxRzRKkxQ7NzALKtYBbjjxNuUnc-h9ycIIceDLjyaszmjFqZKa38UQKU6iywvDmKp5NIBcMagRyCETyRazSupnxaFZCYfAayqjaQ9-Wng5v41DkTO0zjZ8YdWv2_Ie3yA5dGk3UQ8wganQm-MmU4xy0zmgMZ6NJxpmMQ5ZmIP82Ho_Cqk7o2g1RyAqhMi1kpS2taRJCJ6uMcmGSe6LpKr4RqW_fjiAv_Pndlyld47lFnco2LIo8o8TuC9KRJL4iOeGUyVoLK8QehCwIVSBfBlSpLPxFyA2RyYEfI6tPRGRqzXzY217GUnHHr0V0NVmys8ETxw2SjXKj4KKU_tkr6Ze9MfzM1wVBq2ZvCScpgzvnfMTkY0ZZbSY3q4xczo595xHuDhrus0Rw4j6FHR7ocJrsTMKkclcpmryL8lbfx1x2S7fSO-beDUfxO5PnCk3XsFO0lGJt-wzfwX1X8IpUtt8dX4gjAfxL4UjfmN4I-ZDxtBbKvwUfh9-yD_b7UZYDGG7gNZNrkiXwCj9b0hzrFVuDTAMYJmxJTA6v3py_AJQYLWZbTvEAnmPWwGCYdIUHS5IrmJkigXf2OiNgrXW9WhD-U4h1RYEpHjzjJzzo9c-DXjfo9rvtdqffaXUaeIsH7WZw3u0G7XYQ9Hr9oH3ReWngvy5B87x72Wr2Lzuty2brotPu9xqYJfb235ZfEfcxefkHrSAgpg?type=png)](https://mermaid.live/edit#pako:eNqNVV1v2jAU_SuWn2kFKVBg0iRKGUNqpypkq7QxRcYxIWqwM3-UstL_vmvHCdCWai9g-55z77XPsfOMqUgYHuBUkmKFoutPcz7nCCmzKFeG97N4ypeSKC0N1UYyG0box93o1xzDL_pjmNLxY0Hn-Dc6O_u8-0rUDk0n9xCfcs0kZxpNiGYbsvXgdAPYMg_gHCkURjOFIkmWy4zuUBgB3S2iiCxy5plS18wwcsSR4JxRzRKkxQ7NzALKtYBbjjxNuUnc-h9ycIIceDLjyaszmjFqZKa38UQKU6iywvDmKp5NIBcMagRyCETyRazSupnxaFZCYfAayqjaQ9-Wng5v41DkTO0zjZ8YdWv2_Ie3yA5dGk3UQ8wganQm-MmU4xy0zmgMZ6NJxpmMQ5ZmIP82Ho_Cqk7o2g1RyAqhMi1kpS2taRJCJ6uMcmGSe6LpKr4RqW_fjiAv_Pndlyld47lFnco2LIo8o8TuC9KRJL4iOeGUyVoLK8QehCwIVSBfBlSpLPxFyA2RyYEfI6tPRGRqzXzY217GUnHHr0V0NVmys8ETxw2SjXKj4KKU_tkr6Ze9MfzM1wVBq2ZvCScpgzvnfMTkY0ZZbSY3q4xczo595xHuDhrus0Rw4j6FHR7ocJrsTMKkclcpmryL8lbfx1x2S7fSO-beDUfxO5PnCk3XsFO0lGJt-wzfwX1X8IpUtt8dX4gjAfxL4UjfmN4I-ZDxtBbKvwUfh9-yD_b7UZYDGG7gNZNrkiXwCj9b0hzrFVuDTAMYJmxJTA6v3py_AJQYLWZbTvEAnmPWwGCYdIUHS5IrmJkigXf2OiNgrXW9WhD-U4h1RYEpHjzjJzzo9c-DXjfo9rvtdqffaXUaeIsH7WZw3u0G7XYQ9Hr9oH3ReWngvy5B87x72Wr2Lzuty2brotPu9xqYJfb235ZfEfcxefkHrSAgpg)
### 2.2 Justification for the Approach Taken

Initially, the plan was to deploy the application as an **AWS Lambda function**. However, after evaluating constraints and requirements, I transitioned to an **ECS (Elastic Container Service) approach using AWS Fargate**.

| Factor                | AWS Lambda                                    | ECS Fargate (Chosen)                      |
|-----------------------|-----------------------------------------------|-------------------------------------------|
| **Execution Model**   | Event-driven (cold starts, time limits)       | Persistent containerized workloads        |
| **State Management**  | Stateless, requires S3/DynamoDB for state     | Containers maintain state in-memory       |
| **Performance**       | Cold start latency in some cases              | Lower startup latency                     |
| **Networking**        | No persistent VPC IP, must use ALB            | Runs inside VPC with direct networking     |
| **Deployment**        | Runtime-specific packaging (ZIP)              | Full Docker container support              |
| **Scaling**           | Automatic scaling, pay-per-execution          | Manual scaling or auto-scaling available   |
| **Cost Efficiency**   | Cheaper for small workloads                   | Better for long-running processes          |

#### Reasons for Choosing ECS Fargate:
- **Greater control over networking**:
	- Lambda does not retain a static IP, complicating outbound network filtering.
- **Long-running processes**:
	- Lambda has a 15-minute execution limit, whereas ECS Fargate containers can run indefinitely.
- **Easier debugging**:
	- Containers log directly to CloudWatch and can offer shell access for troubleshooting.
- **More flexibility in application packaging**:
	- Lambda requires ZIP-based deployments, while ECS supports full Docker images.

---

## 3. The Ideal Approach (If Using AWS Lambda)

Had AWS Lambda been used, the approach would have been structured as follows:

[![](https://mermaid.ink/img/pako:eNqVVW1v2jAQ_iuWP-wTrcprgUmTKKwdEptQ07VSA0ImMWA1sTO_lLLS_76zQyAJ6YdFQtjn5x7fnZ-z33EgQor7eC1JskEPo68zjuBTZplaBk_eYsxXkigtTaCNpCmgAPpF9VbIl9OK_R6nQx9-c3Rx8W0_FFwTxtUeeWbJqVb-1CwjFqAvaCrZK9E0W5gXWQ5WS4I8GhjJ9O5OCpMoP5uidJ5zpDw8TSriHYo4MZoWd5qQeBkSP_1Dt4YHmgnuwkfjwc97EVH_-xvsac3WgqzpP3b1tJBkXdrVay48Den7XhPdmOCFanSBHqiUZCVkjNxaGsNox0ksRje-s6GJCF4YXwM6W5ifMR9SylMf0nseT1PWdF5KoiJ4yLdIfyiJO907STicUUJlzJSC8iikxf6Mu-w2CAKqFAVRDCNhwieig41_GkKK67NTrQhtIki4uCER4QGVxd0Gkxt_kCQgNOJOzUJRBk2VeS9ACQo9QMFXLNijByLXVDtJ-ek41VepujmYo7kVcktkqNA9_WOo0mpfXdpSIsck7pj-YZaLgROdOjlNjdr4I_pKIwHldVOIdghNm57fcLwYjhZP0H2rSGz9lAYdaFBmzwVfdHAczyw5KAVGmULcFie3I8Z5_E4iqKTX9NOBlROcOEhuXtUBGdq5HrU95kz794bn1G5NOYYCtOj8SCIW2rYpEmTmKpJsrUg0YbwchTVVEVh70XkKQio5W1OVs7UXna0udyVvZ6usYdEt17ogDijvDu7gbXZ0j1TaJpyfqe1I4udqTg5X9FSKV-aad1-80E_YMqxwj34OK1x8n8OOV8znkFKrp_AKRecSlWy9hsY5Wua4hmO4qAgL4dl7txQzrDc0pjPch2FIV8REeoZn_AOgxGjh7XiA-_D-0RqGhl9vcH9FIgUzk1hFjRiBJo6P1oTwZyHizAWmuP-O33C_27tsdDuNTq_TarV77Xq7hne437pqXHY6jVar0eh2e41Ws_1Rw38dwdVl57p-1btu16-v6s12q9etYRoyqOfP9Nl2r_fHPxDFeUE?type=png)](https://mermaid.live/edit#pako:eNqVVW1v2jAQ_iuWP-wTrcprgUmTKKwdEptQ07VSA0ImMWA1sTO_lLLS_76zQyAJ6YdFQtjn5x7fnZ-z33EgQor7eC1JskEPo68zjuBTZplaBk_eYsxXkigtTaCNpCmgAPpF9VbIl9OK_R6nQx9-c3Rx8W0_FFwTxtUeeWbJqVb-1CwjFqAvaCrZK9E0W5gXWQ5WS4I8GhjJ9O5OCpMoP5uidJ5zpDw8TSriHYo4MZoWd5qQeBkSP_1Dt4YHmgnuwkfjwc97EVH_-xvsac3WgqzpP3b1tJBkXdrVay48Den7XhPdmOCFanSBHqiUZCVkjNxaGsNox0ksRje-s6GJCF4YXwM6W5ifMR9SylMf0nseT1PWdF5KoiJ4yLdIfyiJO907STicUUJlzJSC8iikxf6Mu-w2CAKqFAVRDCNhwieig41_GkKK67NTrQhtIki4uCER4QGVxd0Gkxt_kCQgNOJOzUJRBk2VeS9ACQo9QMFXLNijByLXVDtJ-ek41VepujmYo7kVcktkqNA9_WOo0mpfXdpSIsck7pj-YZaLgROdOjlNjdr4I_pKIwHldVOIdghNm57fcLwYjhZP0H2rSGz9lAYdaFBmzwVfdHAczyw5KAVGmULcFie3I8Z5_E4iqKTX9NOBlROcOEhuXtUBGdq5HrU95kz794bn1G5NOYYCtOj8SCIW2rYpEmTmKpJsrUg0YbwchTVVEVh70XkKQio5W1OVs7UXna0udyVvZ6usYdEt17ogDijvDu7gbXZ0j1TaJpyfqe1I4udqTg5X9FSKV-aad1-80E_YMqxwj34OK1x8n8OOV8znkFKrp_AKRecSlWy9hsY5Wua4hmO4qAgL4dl7txQzrDc0pjPch2FIV8REeoZn_AOgxGjh7XiA-_D-0RqGhl9vcH9FIgUzk1hFjRiBJo6P1oTwZyHizAWmuP-O33C_27tsdDuNTq_TarV77Xq7hne437pqXHY6jVar0eh2e41Ws_1Rw38dwdVl57p-1btu16-v6s12q9etYRoyqOfP9Nl2r_fHPxDFeUE)

### 3.1 Why This Was the Ideal Approach for AWS Lambda

- **GitHub Actions CI/CD Pipeline**
	- Automates **Terraform validation, formatting, and deployment**.
	- Ensures that **Lambda deployments** are uploaded to **S3** and provisioned using **Terraform**.
- **S3 + DynamoDB for State & Deployment**
	- **Terraform state** stored in **S3** ensures **version control**.
	- **Lambda deployment ZIP** stored in **S3** allows **faster updates**.
	- **DynamoDB ensures state-locking** for concurrent **Terraform runs**.
- **AWS ALB & API Gateway Integration**
	- The **ALB forwards HTTP traffic** to **Lambda via a Target Group**.
	- Alternatively, **API Gateway** could be used for finer-grained control.
- **Fully Managed Scaling**
	- **Lambda auto-scales automatically** based on request volume.
	- No need for **manual scaling** (as required in ECS).

---

## 4. Trade-offs and Challenges

| Challenge                        | Solution Implemented                                  |
|----------------------------------|------------------------------------------------------|
| **Lambda Cold Starts**           | Moved to ECS to ensure low-latency startup.          |
| **Lambda Execution Limit (15min)** | ECS allows indefinite runtime for services.         |
| **No Static IP in Lambda**       | ECS runs within a VPC, allowing better control.       |
| **Stateful Processing Needs**    | ECS containers can maintain in-memory state.          |
| **Custom Dependencies**          | ECS uses Docker images, avoiding Lambda layer size limitations. |

---

## 5. Technical Documentation: Setting Up Terraform on AWS

Below is my comprehensive documentation detailing the processes, challenges, and solutions I encountered while setting up my AWS infrastructure using Terraform. It describes my journey—from initially trying to use a Lambda function to eventually deploying my containerized application on ECS (Fargate) with an ECR repository.

### 5.1 Initial Attempt: Lambda Function

#### Motivation:
I started with the idea of using a Lambda function. This approach seemed appealing for a smaller service, and I was hoping that the cold start delays (around 200ms) would be acceptable.

#### Issue Encountered: 
While setting up the Lambda, I ran into unexpected problems. I noted: *“I ran into an issue when creating the Lambda function so that may not be the best approach.”*

#### Decision:
Because of these complications—and since one of the requirements was to use a Dockerfile—I decided to pivot away from Lambda. Instead, I focused on building a Docker container image that could run in ECS, still allowing an AWS-based deployment.

**Original Lambda-Based Architecture Diagram:**

[![](https://mermaid.ink/img/pako:eNqVVG1rIjEQ_ish0Ptki66r1T048OVaBHuIK1foKhKzo4a6yV5e2lr1v192o9W1J1wDy87Lk5nMzJNsMBUx4AAvJEmXaNT9PubILmVmztJ6DKc9PpdEaWmoNhIcoAD6BfpVyOejJ1u_B53IfhN0ff1j2xFcE8bVFoVmxkGraGBmK0bRNzSQ7IVoODgmxSh7axYEhUCNZHp9L4VJVXRQkdNPNgKPj8o_ztsRSWo0FDP1STKLSeR-6M5wqpng-fFRr_UwFCuIfr7ZnJk5s6DM9IWsoRaSLM6yhtVpqG35UVhFbUOfQaNrNAIpyVzIBOU-d4bumpNEdNtRbkN9QZ8ZX1j0wTH5FHlf0mnofXlPvYGL6vT_L8LWXUyzb00-5XtJuJ1VCjJhStk2KaTF9lOO820tSkEpsOTorISJH4mmy-go2lIXX5luX5B42iYrwinIYtZWvx210tQSj-RTzKDoAHVMHQrLDIVGdgBzRrdoROQCdE6xyMmOb2fdPoHlYe6EfCUyVmgIfwworbaXW50LTry6Qg8iNrYxMaTWDpwyUM73wYroyI8e2V-wgRQvLG_5tngdj9hzWOEWXIYVaHsZ9kGMy5DCYHAJJ5YnhMX29dlkW8dYLyGBMQ6sGMOcmJUe4zHfWSgxWoRrTnFgnyEoYdvnxRIHc7JSVjNpbK9ElxFLgOQASQl_EuJUxcEGv-Gg0bzxGnWv3qz7fq1Zq9RKeI0Dv-zd1Oue73teo9H0_GptV8LveYDyTf22Um7e1iq35Uq15jcbJQwxs315cI9n_obu_gLwvKWQ?type=png)](https://mermaid.live/edit#pako:eNqVVG1rIjEQ_ish0Ptki66r1T048OVaBHuIK1foKhKzo4a6yV5e2lr1v192o9W1J1wDy87Lk5nMzJNsMBUx4AAvJEmXaNT9PubILmVmztJ6DKc9PpdEaWmoNhIcoAD6BfpVyOejJ1u_B53IfhN0ff1j2xFcE8bVFoVmxkGraGBmK0bRNzSQ7IVoODgmxSh7axYEhUCNZHp9L4VJVXRQkdNPNgKPj8o_ztsRSWo0FDP1STKLSeR-6M5wqpng-fFRr_UwFCuIfr7ZnJk5s6DM9IWsoRaSLM6yhtVpqG35UVhFbUOfQaNrNAIpyVzIBOU-d4bumpNEdNtRbkN9QZ8ZX1j0wTH5FHlf0mnofXlPvYGL6vT_L8LWXUyzb00-5XtJuJ1VCjJhStk2KaTF9lOO820tSkEpsOTorISJH4mmy-go2lIXX5luX5B42iYrwinIYtZWvx210tQSj-RTzKDoAHVMHQrLDIVGdgBzRrdoROQCdE6xyMmOb2fdPoHlYe6EfCUyVmgIfwworbaXW50LTry6Qg8iNrYxMaTWDpwyUM73wYroyI8e2V-wgRQvLG_5tngdj9hzWOEWXIYVaHsZ9kGMy5DCYHAJJ5YnhMX29dlkW8dYLyGBMQ6sGMOcmJUe4zHfWSgxWoRrTnFgnyEoYdvnxRIHc7JSVjNpbK9ElxFLgOQASQl_EuJUxcEGv-Gg0bzxGnWv3qz7fq1Zq9RKeI0Dv-zd1Oue73teo9H0_GptV8LveYDyTf22Um7e1iq35Uq15jcbJQwxs315cI9n_obu_gLwvKWQ)

### 5.2 Building a Docker Container

#### Corepack/Pnpm Error and Resolution

I created a multi-stage Dockerfile using Node.js 22-slim. However, when I built the image, I encountered this error:

```sh
Error: Cannot find matching keyid: {"signatures":[{"sig":"MEYCIQDqo/55uI8Wf6M4RGn3wszRvnxozJXgQK3vMFN/1emK+AIhAOZdugJH0o6Gv0QdU3iAPB67UBlDtAp6EtXoMiVasB2t","keyid":"SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U"}], ...}
```

- **Root Cause:**
	- There was a Corepack signature validation issue with pnpm. Corepack’s integrity keys were outdated, which caused the Docker build to fail.

- **Initial Dockerfile (snippet):**
```Dockerfile
# Stage 1: Base image
FROM node:22-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

# ...
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile --prod
```

This approach triggered the *“Cannot find matching keyid”* error.

- **Resolution:**
	- I updated Corepack to the latest version, explicitly installed pnpm, and pinned them in my Dockerfile to bypass the signature validation problem.

#### Final Dockerfile

I eventually settled on this Dockerfile:
```Dockerfile
# Use Node.js 22 as the base image
FROM node:22 AS base

# Set environment variables for pnpm
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Enable Corepack and install pnpm
RUN npm install -g corepack@latest && corepack enable
RUN corepack prepare pnpm@latest --activate

# Set the working directory inside the container
WORKDIR /app

# Copy package.json and pnpm-lock.yaml to install dependencies
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --frozen-lockfile --prod

# Copy application source code and rename 000.js to index.js
COPY src/000.js /app/index.js

# Copy bin directory
COPY bin/ /app/bin/

# Set execute permissions for scripts in bin
RUN chmod +x /app/bin/*

# Debugging: List files in /app after copying
RUN ls -l /app

# Expose the port your app runs on
EXPOSE 3000

# Run the app
CMD ["node", "/app/index.js"]
```

#### Local Docker Build & Run Issues

- Port Conflict:
	- I encountered this error:
```Dockerfile
docker: Error response from daemon: driver failed programming external connectivity …
Bind for 0.0.0.0:3000 failed: port is already allocated.
```

- Solution:
	- I resolved this conflict by terminating the process that was already using port 3000.

- **Confusion About Application Type:**
	- At that point, I wasn’t completely sure whether my application was purely an HTTP server or a function-like service. Ultimately, I decided to keep the container as a server listening on port 3000.

##### Automation with a Shell Script

To avoid typing the same Docker commands repeatedly, I wrote a bash script named [setups.sh](../setup.sh):
```sh
#!/bin/sh

docker build -t quest_lambda_app .
docker run -d -p 3000:3000 quest_lambda_app
docker ps --format '{{.Names}}' | grep -w "^quest_lambda_app$"
```

- **Purpose:**
	1.	Build the Docker image (quest_lambda_app).
	2.	Run it in detached mode, mapping host port 3000.
	3.	Verify that the container is running.

### 5.3 Pivot to ECS and ECR

Once my Docker image worked locally, I moved on to deploying it on ECS (Fargate) and storing the container image in ECR.

#### GitHub Actions & AWS Credentials

- **Problem:**
	- In my GitHub Actions pipeline, I encountered AWS credential errors when attempting to push images to ECR. I noted: *“I think the issue is that I need to setup OIDC authentication.”*

- **Resolution:**
	- I discovered that I had misspelled an environment variable. Once I corrected it, the credential issues were resolved, and I was able to deploy to ECS.

#### ECR Registry (Private vs. Public) and ECS Pull Issues

##### ResourceInitializationError:
- My ECS tasks were failing with:
```txt
ResourceInitializationError: unable to pull secrets or registry auth: The task cannot pull registry auth from Amazon ECR…
```

###### Possible Causes:
1.	**Network:** My ECS tasks might have been in private subnets without a NAT Gateway.
2.	**Security Group:** Outbound internet traffic might have been blocked.
3.	**IAM Role:** The ECS Task Execution Role might have been missing the AmazonECSTaskExecutionRolePolicy.

##### Public vs. Private ECR:
- After facing persistent time constraints and misconfiguration issues with the private registry, I considered switching to a public ECR registry. However, I ultimately resolved the authentication challenges with the private registry, enabling ECS tasks to pull images reliably.

#### Networking & Subnet Challenges
##### Changing CIDR Blocks:
- I attempted to change my subnets from a `/24` to a larger` /20` CIDR. However, Terraform refused to delete subnets that were still associated with an Elastic Load Balancer (ELB).

 ##### Error:
- DependencyViolation: The subnet ‘subnet-0fe84a78b72b33891’ has dependencies and cannot be deleted.

##### Diagnosis:
- I found that the subnet was still tied to an ELB. I had to manually deregister the ELB and delete it before I could remove the subnet.

##### ALB & Target Group:
- Even after cleaning up, my ECS tasks were not registering in the target group. Running `aws elbv2 describe-target-health` returned an empty list, indicating that no tasks were registered because they had either stopped or failed to launch.

#### CI/CD Pipeline Refinements [^1]
1.	**Lifecycle & Data Sources in Terraform:**
	- I added lifecycle blocks to prevent Terraform from accidentally destroying existing resources.
	- I used data sources to detect if resources already existed so that Terraform wouldn’t recreate them unnecessarily.
2.	**Selective Terraform Execution:**
	- I modified my GitHub Actions pipeline to run terraform apply only when there were changes to my .tf files. This prevented unnecessary redeployments on every code push.

#### IAM Roles: Task Execution Role vs. Task Role

After some investigation—and with help from the AltF4 Discord server—I clarified that two IAM roles are essential for ECS:
1.	**Task Execution Role (Required):**
- Grants ECS permission to pull the container image from ECR, write logs to CloudWatch, etc.
- Must include the AmazonECSTaskExecutionRolePolicy.
2.	**Task Role (Optional):**
- Used if the running container needs additional permissions (e.g., accessing DynamoDB, S3, etc.).

I realized that my issue wasn’t with the task role at all; I had mistakenly assigned a `task_role_arn` when what I really needed was to set the `execution_role_arn`. I corrected this by assigning the ECS execution role—with the necessary permissions—so that ECS could pull images from ECR, write logs, and launch tasks properly.

My original Terraform configuration was missing several critical settings:
- **Missing IAM permissions:** I attached the AWS-managed IAM policy `AmazonECSTaskExecutionRolePolicy` to my ECS execution role.
- **Incorrect network configurations:** I explicitly set `map_public_ip_on_launch = true` for my subnets and added proper route table associations for internet access.
- **Incomplete ECR repository policies:** I updated the policy to explicitly grant the ECS execution role permission to pull images.
- I also added an output variable for the ECR repository URL for easier verification of image availability.

## 5.4 Final Terraform Solution & Architecture Diagram

### Final Terraform Fixes

- I removed the `task_role_arn` from my ECS task definition and instead set the `execution_role_arn` to point to my ECS execution role.
- I attached the `AmazonECSTaskExecutionRolePolicy` to the ECS execution role to grant the necessary permissions (pulling images from ECR, writing logs to CloudWatch, etc.).
- I explicitly set my subnets to have `map_public_ip_on_launch = true` and ensured that route table associations provided proper internet access.
- I updated my ECR repository policy to explicitly allow the ECS execution role to pull images.
- I added an output variable for the ECR repository URL for easier verification of image availability.

## Architecture Diagrams

### Original Lambda-Based Architecture

[![](https://mermaid.ink/img/pako:eNqVVNtu4jAQ_RXLUveJVhAChay0EpdthURXiKCt1FBVxhnAKrGzvrRlS_99Jwm3UPqwlqJ4Zo7neux3ylUMNKALzdIlmfS_TyXBZdys0HTuw6eBnGtmrHbcOg0FoAT6BfZV6eeDJVu_R70Iv0dyeflj01PSMiHNhoRuJsGaaORmK8HJNzLS4oVZ2Bkey1622swJCYE7Lez6ViuXmmgnkkI-OggyPghn8u2pJHUWypGGLJnFLCp-5MZJboWSefpk0LkbqxVEP98wZqbONCRT_UfU0CrNFidRw_pTaLH8KKyTruPPYMklmYDWbK50QnJbkUN_LVmi-t0o15Gh4s9CLhC9Mzx-8rwt6dj1tryHwajwWsgnRZxJHustu9-2JJ_urWYSZ5SCToQx2B5DrNp88n16rMM5GANIit5KufieWb6MDlsscfFpqmdSGyoWP3XZikkOuhytM-xGnTRForF8ahmU7KAFM8cKmWDIBBs-F3xDJkwvwOaUiop9wa-T7h7Bcjc3Sr8yHRsyhj8OjDWb8609KeTigtyp2GFDYkhRD5ILMIVtz4LowIcB216okVYvIm_1pnz9DthTWIn1X8NKNP0atifE15DSYGiFJsgPJmJ8bd6zo1Nql5DAlAa4jWHO3MpO6VR-IJQ5q8K15DTAZwcqFPu8WNJgzlYGJZfGeAX6giEBkr02ZfJBqWR3BEUavNM3GrTaV16r6TXbTd9vtBu1RoWuaeBXvatm0_N9z2u12p5fb3xU6N_cQfWqeV2rtq8btetqrd7w260KhVhgY-6K1zJ_ND_-AUbNo9s?type=png)](https://mermaid.live/edit#pako:eNqVVNtu4jAQ_RXLUveJVhAChay0EpdthURXiKCt1FBVxhnAKrGzvrRlS_99Jwm3UPqwlqJ4Zo7neux3ylUMNKALzdIlmfS_TyXBZdys0HTuw6eBnGtmrHbcOg0FoAT6BfZV6eeDJVu_R70Iv0dyeflj01PSMiHNhoRuJsGaaORmK8HJNzLS4oVZ2Bkey1622swJCYE7Lez6ViuXmmgnkkI-OggyPghn8u2pJHUWypGGLJnFLCp-5MZJboWSefpk0LkbqxVEP98wZqbONCRT_UfU0CrNFidRw_pTaLH8KKyTruPPYMklmYDWbK50QnJbkUN_LVmi-t0o15Gh4s9CLhC9Mzx-8rwt6dj1tryHwajwWsgnRZxJHustu9-2JJ_urWYSZ5SCToQx2B5DrNp88n16rMM5GANIit5KufieWb6MDlsscfFpqmdSGyoWP3XZikkOuhytM-xGnTRForF8ahmU7KAFM8cKmWDIBBs-F3xDJkwvwOaUiop9wa-T7h7Bcjc3Sr8yHRsyhj8OjDWb8609KeTigtyp2GFDYkhRD5ILMIVtz4LowIcB216okVYvIm_1pnz9DthTWIn1X8NKNP0atifE15DSYGiFJsgPJmJ8bd6zo1Nql5DAlAa4jWHO3MpO6VR-IJQ5q8K15DTAZwcqFPu8WNJgzlYGJZfGeAX6giEBkr02ZfJBqWR3BEUavNM3GrTaV16r6TXbTd9vtBu1RoWuaeBXvatm0_N9z2u12p5fb3xU6N_cQfWqeV2rtq8btetqrd7w260KhVhgY-6K1zJ_ND_-AUbNo9s)


### Extended Lambda-Based Architecture with CI/CD (If I Had More Time)

[![](https://mermaid.ink/img/pako:eNqVVW1v2jAQ_iuWpe0TrcprgUmTKKwdEp1Q07VSA0ImMWA1sTO_tGWl_31nh0AS0g-LhLAf3z32nZ87v-NAhBT38VqSZIPuR99mHMGnzDJFBo_eYsxXkigtTaCNpKlBwegX1a9CPh9X7PcwHfrwm6Ozs--7oeCaMK52yDNLTrXyp2YZsQB9RVPJXoim2cK8yLJHLQnyaGAk09sbKUyi_GyK0nnOkfLwOKk471DEidG0uNOExMuQ-OkfujY80Exwd3w0HtzeiYj6P95gTwtbBFnoP3b1tJBkXdrVay48DeH7XhNdmeCZanSG7qmUZCVkjNxaeobRlpNYjK58h6GJCJ4ZX4N1tjA_Yd6HlKfeh_c0nqas6bwURMXhId4i_T4l7nZvJOFwRwmVMVMK0qOQFrsT7rLbIAioUhREMYyECR-JDjb-cQghrk9uteJoE0HCxRWJCA-oLO42mFz5gyQBoRF3a9YUZaapMu8EKEGhe0j4igU7dE_kmmonKT8dp_oqZTdn5miuhXwlMlTojv4xVGm1q05tKZBDEDdM_zTLxcCJTh2dpkZt_BF9oZGA9LopnHYIRZve33C8GI4Wj1B9q0i8-ikN2tOgDM8dvujgOJ5YslcKjDKFuC2Obgcb5_E7iSCTXtNPB1ZOcOMguXlVBWTWzvWg7TFn2r8zPKd2C-UYCqZF5wcSsdCWTZEgg6tIsrUi0YTx8iksVEVg8aLzFIRUcrZQlbPFi85Wl9uSt8Mqc1h0y5UuiAPSu4Ue_Jpd3QOVtgjnJ2r78gXditBA-YU0AZzygNG92A4b-Ln7IPv2PZXihbnC3hWb_dG2bFbosZ-bFZri52aH9vO5SakNpOYVas8FKtl6DUV1QOa4hmNoYoSF8CS-W4oZ1hsa0xnuwzCkK2IiPcMz_gGmxGjhbXmA-_A20hqGZrDe4P6KRApmJrFqGzECBR4f0ITwJyHizAWmuP-O33C_2ztvdDuNTq_TarV77Xq7hre437ponHc6jVar0eh2e41Ws_1Rw38dwcV557J-0bts1y8v6s12q9etYRoyyOdt-qS7l_3jH53CgmI?type=png)](https://mermaid.live/edit#pako:eNqVVW1v2jAQ_iuWpe0TrcprgUmTKKwdEp1Q07VSA0ImMWA1sTO_tGWl_31nh0AS0g-LhLAf3z32nZ87v-NAhBT38VqSZIPuR99mHMGnzDJFBo_eYsxXkigtTaCNpKlBwegX1a9CPh9X7PcwHfrwm6Ozs--7oeCaMK52yDNLTrXyp2YZsQB9RVPJXoim2cK8yLJHLQnyaGAk09sbKUyi_GyK0nnOkfLwOKk471DEidG0uNOExMuQ-OkfujY80Exwd3w0HtzeiYj6P95gTwtbBFnoP3b1tJBkXdrVay48DeH7XhNdmeCZanSG7qmUZCVkjNxaeobRlpNYjK58h6GJCJ4ZX4N1tjA_Yd6HlKfeh_c0nqas6bwURMXhId4i_T4l7nZvJOFwRwmVMVMK0qOQFrsT7rLbIAioUhREMYyECR-JDjb-cQghrk9uteJoE0HCxRWJCA-oLO42mFz5gyQBoRF3a9YUZaapMu8EKEGhe0j4igU7dE_kmmonKT8dp_oqZTdn5miuhXwlMlTojv4xVGm1q05tKZBDEDdM_zTLxcCJTh2dpkZt_BF9oZGA9LopnHYIRZve33C8GI4Wj1B9q0i8-ikN2tOgDM8dvujgOJ5YslcKjDKFuC2Obgcb5_E7iSCTXtNPB1ZOcOMguXlVBWTWzvWg7TFn2r8zPKd2C-UYCqZF5wcSsdCWTZEgg6tIsrUi0YTx8iksVEVg8aLzFIRUcrZQlbPFi85Wl9uSt8Mqc1h0y5UuiAPSu4Ue_Jpd3QOVtgjnJ2r78gXditBA-YU0AZzygNG92A4b-Ln7IPv2PZXihbnC3hWb_dG2bFbosZ-bFZri52aH9vO5SakNpOYVas8FKtl6DUV1QOa4hmNoYoSF8CS-W4oZ1hsa0xnuwzCkK2IiPcMz_gGmxGjhbXmA-_A20hqGZrDe4P6KRApmJrFqGzECBR4f0ITwJyHizAWmuP-O33C_2ztvdDuNTq_TarV77Xq7hre437ponHc6jVar0eh2e41Ws_1Rw38dwcV557J-0bts1y8v6s12q9etYRoyyOdt-qS7l_3jH53CgmI)


### Final ECS-Based Architecture

[![](https://mermaid.ink/img/pako:eNqVVwtv2zYQ_iuEihYdICe2_EisDkX9imMgHQLbW4DZhUBLtExEFjWJSuomBfZb9tP2S3ZHvWV7RRFAIXl3H-_N84tmC4dpprb1xLO9o6Eky_HaX_uEvH1LRrPL0ZiMhC8p91mIp1G8cUMa7IBmAW015fI23pCBLbnwI3LPA-YBbyH0BaVKctNbK2OuCz-I8BH1SEUIGazu4wiuEvs9l0QKsqeRZCHZhNS3dznbcLUMuesC4QhhtFprox2zH0UsyZwFIuJShIf12n9Pk1sv7ZT86anzy1rLJccoKfwtd-OQkcHDgoxC5jBfcupFSv45auQYGWMDT-2C8dOTUQadAOidcAn30ZrBnn4TPpmM5nU8qigNZocNT7jc__TUKsPcAMww5p5D3hHlobGwH8H82Z66DLD-_fsf4iRHG8XWkOTXkLk8kuHh4-VfMYtkw84i1Ahzv5gelUAjF1WQAO8AhVHTQospaPF74IAEEBZkwcInbuP178csskO-YTr5LBy-PejgerwcoJY0eiRjtuU-R1PLVg1Io_GRDNV3pL5j9Z2o7436ThNm5ju4UP_SXMUIpSpEZ1IWWKycQlanJb4kiArzNyafIaO474Kj_7gf1VIZTqwSywr2wFec5JYBAXwFX5Mo31tPgY1-Gs3Gc5O0mhfq77LVK7tjNn0AoZkPXvOZJFPw8zM9ZAjuc4l1vgTOOeQwA_9uPJYxhbLEtIg3gNMCzmSVMUVqZ7VqCrVAIaNSEYmYcQ7AqAEYRwDoHwwiWFYyUh3Nl4Ut6iDV9uSpUUqCPFYLZschlwdCfYfMBp9rscrIFpDIKmd-h6y5gsfc01DEQVQSSA5yCcjau6G1wFKABamymYR6Gyty0TEz3w1ZFJnkuql3Ou2yWwiWT4KR1FEVg9lRHaPdbDbLCGk5VEwAu6y58CC1V2iyWtaunHxltuLBPEt5kvskVKnFgBxjkeLd9yzc8yjC7mRiH9AJ9LFIR5yTmlSDMwgCj9sUwfKSqwWoxGLlVbk6JXgcLtDHgrBbqBJZwQ7iOvJE7DxQWXon0Oq58vK89BZkaZz3Qwv7YSU-iIvPQQ6JJ1l8EmnlMejV0Q_Cgn4feTH2wiS5UF94W5Ij0Du1shaqlJ6mSLrL7oaIHadTApPnlNrlFVu06hsautBZjvMRG3UqjcuynarQM2-lhOI50cm9COVxklYMSRp7oedJ5XMmVOBYO0XG0Jwh4Wt1jlJK_v-LFhZ3GqVyJt4J6pAh9WAKyQectBdgIzjHmfkQukLFL0ss_SUEAtt8JalU2Rfu1Mkto56EiQhnlqpzsf2gbctpvTepY1ieMLTu7EL4VBgW01O1XXoBIQd8lg5z21DsVcdPnodIDTxn20Da7vGq1wLwtVA77fw_YjhGOEqyc0gVxvp0ccf9x3QcRjseFnheGmURbMwCTxxIMhI5yTD2WsrfFGohDx46aytCInzW8NgT84jDWEB8CDpI5qWknGN7NIpgYiLuLr0NERjZcs8z3wwm495NS4fBTjwy80273U7XjWfuyJ1pBF8_VFBg9CisriANJ8NR7yeQovShmtF9GeemP7nq3_wEDg2CLBkqON3h1fCHluVI5WhUPVXcVp_Yjn1R4q1MDHVbS3wnH666TR80XdvDE0q5Az-2XlB6rckd27O1ZsLSYVsaezCurf3vwEpjKRYH39ZMGcZM16ApuDvN3MIvCtjFKsPGnEKT2uenAfX_FGKficBWM1-0r5p53b8wrntGr9_rdLr9bqurawfN7DSNi17P6HQM4_q6b3Ta3e-69k0BNC96V61m_6prdFvGVeu62dY15uBj-Tn5sah-M37_DwN4lF8?type=png)](https://mermaid.live/edit#pako:eNqVVwtv2zYQ_iuEihYdICe2_EisDkX9imMgHQLbW4DZhUBLtExEFjWJSuomBfZb9tP2S3ZHvWV7RRFAIXl3H-_N84tmC4dpprb1xLO9o6Eky_HaX_uEvH1LRrPL0ZiMhC8p91mIp1G8cUMa7IBmAW015fI23pCBLbnwI3LPA-YBbyH0BaVKctNbK2OuCz-I8BH1SEUIGazu4wiuEvs9l0QKsqeRZCHZhNS3dznbcLUMuesC4QhhtFprox2zH0UsyZwFIuJShIf12n9Pk1sv7ZT86anzy1rLJccoKfwtd-OQkcHDgoxC5jBfcupFSv45auQYGWMDT-2C8dOTUQadAOidcAn30ZrBnn4TPpmM5nU8qigNZocNT7jc__TUKsPcAMww5p5D3hHlobGwH8H82Z66DLD-_fsf4iRHG8XWkOTXkLk8kuHh4-VfMYtkw84i1Ahzv5gelUAjF1WQAO8AhVHTQospaPF74IAEEBZkwcInbuP178csskO-YTr5LBy-PejgerwcoJY0eiRjtuU-R1PLVg1Io_GRDNV3pL5j9Z2o7436ThNm5ju4UP_SXMUIpSpEZ1IWWKycQlanJb4kiArzNyafIaO474Kj_7gf1VIZTqwSywr2wFec5JYBAXwFX5Mo31tPgY1-Gs3Gc5O0mhfq77LVK7tjNn0AoZkPXvOZJFPw8zM9ZAjuc4l1vgTOOeQwA_9uPJYxhbLEtIg3gNMCzmSVMUVqZ7VqCrVAIaNSEYmYcQ7AqAEYRwDoHwwiWFYyUh3Nl4Ut6iDV9uSpUUqCPFYLZschlwdCfYfMBp9rscrIFpDIKmd-h6y5gsfc01DEQVQSSA5yCcjau6G1wFKABamymYR6Gyty0TEz3w1ZFJnkuql3Ou2yWwiWT4KR1FEVg9lRHaPdbDbLCGk5VEwAu6y58CC1V2iyWtaunHxltuLBPEt5kvskVKnFgBxjkeLd9yzc8yjC7mRiH9AJ9LFIR5yTmlSDMwgCj9sUwfKSqwWoxGLlVbk6JXgcLtDHgrBbqBJZwQ7iOvJE7DxQWXon0Oq58vK89BZkaZz3Qwv7YSU-iIvPQQ6JJ1l8EmnlMejV0Q_Cgn4feTH2wiS5UF94W5Ij0Du1shaqlJ6mSLrL7oaIHadTApPnlNrlFVu06hsautBZjvMRG3UqjcuynarQM2-lhOI50cm9COVxklYMSRp7oedJ5XMmVOBYO0XG0Jwh4Wt1jlJK_v-LFhZ3GqVyJt4J6pAh9WAKyQectBdgIzjHmfkQukLFL0ss_SUEAtt8JalU2Rfu1Mkto56EiQhnlqpzsf2gbctpvTepY1ieMLTu7EL4VBgW01O1XXoBIQd8lg5z21DsVcdPnodIDTxn20Da7vGq1wLwtVA77fw_YjhGOEqyc0gVxvp0ccf9x3QcRjseFnheGmURbMwCTxxIMhI5yTD2WsrfFGohDx46aytCInzW8NgT84jDWEB8CDpI5qWknGN7NIpgYiLuLr0NERjZcs8z3wwm495NS4fBTjwy80273U7XjWfuyJ1pBF8_VFBg9CisriANJ8NR7yeQovShmtF9GeemP7nq3_wEDg2CLBkqON3h1fCHluVI5WhUPVXcVp_Yjn1R4q1MDHVbS3wnH666TR80XdvDE0q5Az-2XlB6rckd27O1ZsLSYVsaezCurf3vwEpjKRYH39ZMGcZM16ApuDvN3MIvCtjFKsPGnEKT2uenAfX_FGKficBWM1-0r5p53b8wrntGr9_rdLr9bqurawfN7DSNi17P6HQM4_q6b3Ta3e-69k0BNC96V61m_6prdFvGVeu62dY15uBj-Tn5sah-M37_DwN4lF8)

---

#### Encrypting SSL Certificates with SOPS & AGE
- [Encrypting SSL Certificates with SOPS & AGE](./Encrypting_SSL_Certificates_With_SOPS_and_AGE.md)

---

#### 1. Final Observations & Conclusion:
1. **Corepack & pnpm:**
  - By pinning Corepack and pnpm to their latest versions in my Dockerfile, I overcame the signature validation errors during the Docker build.
2. **Local Docker Conflicts:**
  - I resolved port conflicts on port 3000 by terminating any processes using that port.
3. **Lambda vs. ECS:**
  - Although I initially tried Lambda, I ultimately pivoted to ECS due to Docker/ECR requirements and the complexities I encountered with Lambda.
4. **Terraform Networking & Subnets:**
  - Deleting or changing subnets often required manual cleanup of ELBs or other resources first. I ensured that my subnets had `map_public_ip_on_launch` set to true and that proper route table associations provided internet access.
5. **ECS Task Pull Failures:**
  - These were often caused by using a private ECR with missing NAT Gateway or misconfigured security groups. Switching to a public ECR simplified the process.
6.	**IAM Roles:**
  - My initial mistake was setting the task_role_arn when I really needed to set the execution_role_arn. I corrected this by assigning the ECS execution role—with the attached `AmazonECSTaskExecutionRolePolicy`—so that ECS could pull images from ECR, write logs to CloudWatch, and launch tasks properly.
7.	**CI/CD Pipeline:**
  - I refined my GitHub Actions pipeline to run Terraform only when there were changes to .tf files and ensured that environment variables (such as ECR_PUBLIC_REGISTRY) were formatted correctly without trailing slashes.
8. **TLS & SSL Certificates**
  - To enforce secure HTTPS traffic, I implemented TLS encryption for the Application Load Balancer (ALB) using self-signed SSL certificates managed with SOPS & AGE. 


The **ECS-based approach** was chosen due to:
1. **More predictable performance** (**no cold starts, persistent compute**).
2. **More control over networking** (**ECS containers live within a VPC**).
3. **Better debugging capabilities** (**logs, direct shell access via AWS Fargate**).
4. **Support for long-running tasks** (**ECS can run continuously, unlike Lambda’s 15-minute limit**).

However, **AWS Lambda would have been ideal** for:
- **Short-lived functions with minimal state**.
- **Minimizing costs for infrequent executions**.
- **Using AWS API Gateway instead of ALB**.

Overall, this extensive debugging and refactoring process led me to a robust ECS-based solution. I now have a Terraform configuration that seamlessly provisions my AWS resources, allowing ECS to pull images from ECR, launch tasks, and operate without networking or permission-related failures. This journey provided me with deep insights into Docker builds, network configurations, IAM, and Terraform best practices on AWS.

## 6. Next Steps
- Evaluate **ECS Auto Scaling** for **cost optimization**.
- Implement **Terraform state locking** with **DynamoDB**.
- Consider storing **Terraform state** in **S3**
- Integrate **CI/CD workflows** to automate **container builds and deployments** only when there are changes to the source code files.
- Integrate **CI/CD workflows** to automate infrastructure changes when code changes are made to the Terraform file.
- Implement TLS with Route53
- Make the Terraform structure more Modular like this [Modular Terraform Directory Structure - Example](./assets/Modular_Terraform_Directory_Structure.png)

This TRD serves as a reference for the **design decisions and trade-offs** made in moving from **Lambda to ECS** and will inform future **infrastructure decisions**. 

1. References
	1. [AWS ECS: Amazon ECS Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html)
	2. [AWS ECR: Amazon ECR Documentation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)
	3. [AWS Lambda: Lambda Documentation](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
	4. [Terraform: Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
	5. Corepack & pnpm:
	    • [Corepack GitHub](https://github.com/nodejs/corepack)
	    • [pnpm Installation Docs](https://pnpm.io/installation)
    

[^1]: I implemented this change and then reverted it after running into issues running terraform locally
