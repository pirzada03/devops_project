terraform {
  backend "s3" {
    bucket = "piri-bucket"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
