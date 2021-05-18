variable "project" { 
  default = "termproject-310217"
}

variable "credentials_file" {
  default = "/Users/darpitchaudhary/Desktop/Advance_Cloud/Google_K8s_Terraform/gke/termproject-310217-091c7ab56ae7.json"
}

variable "getClusterConfig" {
  default = "gcloud container clusters get-credentials gkecluster --region us-east1 --project termproject-310217"
}

variable "region" {
  default = "us-east1"
}

variable "homePath" {
  default = "/Users/darpitchaudhary/Desktop/Advance_Cloud/Google_K8s_Terraform"
}


variable "zoneId" {
  default = "Z0467779JD8BRX6V755V"
}

variable "webappDomain" {
  default = "application1.prod.shubhamkawane.com"
}



variable "dbtier" {
  default = "db-f1-micro"
}

variable "disk_size"{
  type    = number
  default = 10
}

variable "database_version"{
  default = "POSTGRES_13"
}

variable "db_user"{
  default = "postgres"
}

variable "db_password" {
  default = "postgres"
}

variable "gke_username" {
  default     = ""
  description = "gke username"
}

variable "gke_password" {
  default     = ""
  description = "gke password"
}

variable "gke_num_nodes" {
  default     = 2
  description = "number of gke nodes"
}

variable "cluster" {
  default = "gkecluster"
}

variable "min_node_count"{
 default = 1
}

variable "max_node_count"{
 default = 2
}

variable "max_unavailable"{
 default = 0
}

variable "max_surge"{
 default = 1
}

variable "node_machine_type"{
 default = "e2-standard-2"
}

variable "project_services" {
  type = "list"

  default = [
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "sqladmin.googleapis.com",
    "securetoken.googleapis.com",
  ]
  description = <<-EOF
  The GCP APIs that should be enabled in this project.
  EOF
}

variable "zone" {
  default = "us-west1-b"
  description = "The zone in which to create the Kubernetes cluster. Must match the region"
  type        = "string"
}


variable "acme_email" {
  description = "Admin e-mail for Let's Encrypt"
  type        = string
  default = "kawane.s@northeastern.edu"
}

variable "domain_name" {
  description = "Root domain name for the stack"
  type        = string
  default = "shubhamkawane.com"
}

variable "dns_zone_name" {
  description = "The unique name of the zone hosted by Google Cloud DNS"
  type        = string
  default = "shubhamdomain"
}

variable "google_application_credentials" {
  description = "Path to GCE JSON key file (used in k8s secrets for accessing GCE resources). Normally equals to GOOGLE_APPLICATION_CREDENTIALS env var value."
  type        = string
  default = "/Users/darpitchaudhary/Desktop/Advance_Cloud/terraform-gke-csye7225/gke/termproject-310217-091c7ab56ae7.json"
}

variable "google_project_id" {
  description = "GCE project ID"
  type        = string
  default = "csye6225-310222"
}


