####################################
# variables                        #
####################################
variable "resource_group_name" {
    type = string
    default = "mb-tf-rancher-ha"
}

variable "location" {
    type    = string
    default = "northeurope"
}

variable "vnet_cidr_range"{
    type    = list(string)
    default = ["10.0.0.0/16"]
}

variable "subnet_prefixes"{
    type    = list(string)
    default = ["10.0.0.0/24","10.0.1.0/24"]
}

variable "subnet_names"{
    type    = list(string)
    default = ["subnet1","subnet2"]
}

variable "load_balancer_name"{
    type    = string
    default = "mb-rancher-load-balancer"
}

variable "load_balancer_public_ip_name"{
    type    = string
    default = "mb-rancher-load_balancer_public_ip"
}

variable "avset_name"{
    type    = string
    default = "mb-rancher-avset"
}

variable "node_master_count" {
  type        = number
  description = "Master nodes count"
  default     = 0
}

variable "node_worker_count" {
  type        = number
  description = "Worker nodes count"
  default     = 0
}

variable "node_all_count" {
  type        = number
  description = "All roles nodes count"
  default     = 3
}

variable "size" {
  default = "Standard_DS1_v2"
}

variable "prefix" {
  type        = string
  description = "Prefix added to names of all resources"
  default     = "rancher-infra-azure"
}

variable "node_username" {
  type        = string
  description = "Instance type used for all instances"
  default     = "ubuntu"
}

variable "docker_version" {
  type        = string
  description = "Docker version to install on nodes"
  default     = "19.03"
}

variable "nsg_name" {
  default = "rancher-nsg"
}