terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"  # Update this with your bucket name
    key            = "aws-infra/terraform.tfstate"
    region         = "us-east-1"  # Update with your preferred region
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
