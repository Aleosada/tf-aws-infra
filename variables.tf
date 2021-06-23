##################################################################################
# VARIABLES
##################################################################################

variable "private_key_path" {}
variable "key_name" {}
variable "region" {
  default = "sa-east-1"
}
variable "web_network_address_space" {
  type = map(string)
}
variable "shared_network_address_space" {
  type = map(string)
}
variable "transit_network_address_space" {
  type = map(string)
}
variable "nginx_instance_size" {
  type = map(string)
}
variable "nginx_instance_count" {
  type = map(number)
}
variable "db_instance_size" {
  type = map(string)
}
variable "db_instance_count" {
  type = map(number)
}
variable "nat_instance_size" {
  type = map(string)
}
variable "nat_instance_count" {
  type = map(number)
}
variable "web_subnet_count" {
  type = map(number)
}
variable "shared_priv_subnet_count" {
  type = map(number)
}
variable "shared_pub_subnet_count" {
  type = map(number)
}

##################################################################################
# LOCALS
##################################################################################

locals {
  common_tags = {
    Environment = terraform.workspace
    Owner       = "alexandre.osada"
  }
}
