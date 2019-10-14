# Terraform your AWS Deployment
---

Programmed by praz.jain@gmail.com  

If you are developing applications for Cloud, you want to spend most of your time doing exactly that.  

Manually setting up cloud infrastructure for your application, takes away precious time, that you could use to generate end user value. It is error prone, not repeatable and has key man dependency.

Terraform allows to deliver Infrastructure as Code.  

 * You can script your environment state. 
 * Replicate the infrastructure to another environment. 
 * Source control the script to see how infrastructure has evolved over time. 
 * Compare infrastructure state between different environment using terraform state files.

Use the script below to setup a modern cloud infrastructure for your web application.

### Usage

Download the script from this repository, navigate to directory where the script resides and run it as below :

`terraform apply`

It will prompt you for some AWS credentials (secret key, access key, private key path etc).

It will generate :  

 * Virtual Private Cloud (VPC)  
 * Configurable number of Subnets in the VPC
 * Configurable number of Amazon EC2 instances
 * Configurable Amazon Machine Images (AMI) setup on those instances.
 * Amazon EC2 instances and Subnets are spread out over multiple availablility regions
 * Set up Application Load Balancer
 * Install Nginx webserver on EC2 instances 
 * Navigate to the URL shown in script output, if all has gone well, you will see nginx webserver's default web page.
  
To clean up this environment :  

`terraform destroy`
	
### Setup

#### Install Terraform

[Download Terraform](https://www.terraform.io/downloads.html)

#### AWS Setup

 * Make sure you have a user with appropriate permissions 
 * Create access key for this user in AWS web console 
 * Download the key file.