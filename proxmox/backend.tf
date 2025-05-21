terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"  # Update this with your bucket name
    key            = "proxmox-infra/terraform.tfstate"
    region         = "us-east-1"  # Should match your AWS region
    encrypt        = true
    dynamodb_table = "terraform-locks"
    
    # These would typically be set via environment variables
    # access_key = ""
    # secret_key = ""
    # endpoint   = "s3.amazonaws.com"
  }
}

# Configure the Proxmox provider
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}
