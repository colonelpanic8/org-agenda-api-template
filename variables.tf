# Required variables

variable "app_name" {
  description = "Name of the Fly.io application"
  type        = string
}

# Optional configuration

variable "region" {
  description = "Fly.io region (see: fly platform regions)"
  type        = string
  default     = "ord"  # Chicago
}

variable "container_image" {
  description = "Container image to deploy (built and pushed by deploy.sh)"
  type        = string
  default     = ""  # Set dynamically by deploy.sh
}

variable "vm_size" {
  description = "VM size (shared-cpu-1x, shared-cpu-2x, etc.)"
  type        = string
  default     = "shared-cpu-1x"
}

variable "vm_memory" {
  description = "VM memory in MB"
  type        = number
  default     = 512
}

variable "git_sync_interval" {
  description = "Git sync interval in seconds"
  type        = number
  default     = 60
}

variable "custom_elisp" {
  description = "Custom elisp code to evaluate on startup (inline)"
  type        = string
  default     = ""
}

# Note: Secrets (GIT_SYNC_REPOSITORY, GIT_SSH_PRIVATE_KEY, AUTH_USER,
# AUTH_PASSWORD, GIT_USER_EMAIL, GIT_USER_NAME) are managed via agenix
# and set using flyctl secrets in deploy.sh. They are not Terraform variables.
