variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user running Terraform"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the OCI API signing key"
  type        = string
}

variable "private_key_path" {
  description = "Absolute path to the OCI API private key (.pem)"
  type        = string
}

variable "region" {
  description = "OCI region identifier, e.g. ap-mumbai-1"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment where resources will be created"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain for the Always Free A1 instance, e.g. 'kWfj:AP-MUMBAI-1-AD-1'"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Absolute path to the SSH public key to inject into the instance"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "instance_display_name" {
  description = "Display name for the compute instance"
  type        = string
  default     = "sukhi-fedi-prod"
}

variable "ocpus" {
  description = "Number of OCPUs for the A1.Flex shape (max 4 on Always Free)"
  type        = number
  default     = 2
}

variable "memory_in_gbs" {
  description = "RAM in GB for the A1.Flex shape (max 24 on Always Free)"
  type        = number
  default     = 12
}

variable "boot_volume_size_gb" {
  description = "Boot volume size in GB (Always Free: 200 GB total block storage)"
  type        = number
  default     = 100
}

variable "block_volume_size_gb" {
  description = "Attached block volume size in GB for persistent data (postgres, NATS)"
  type        = number
  default     = 50
}
