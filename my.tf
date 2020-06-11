// Telling terraform that we have to launch infrastructure in AWS

provider "aws" {
region = "ap-south-1"
}



// Declaring varible for public key

variable "x" {
  type = string
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCD1kXs/m4M9KrrzMTr2S+2U+MCjaF96BZSFomoDzgVPzB1dZnrYM0oylAS7MQ8JwMJvHX2pWya2Fq11EL2fGJmsvkqB0RqwSoFlM/VsnXb9582dp/
}


// Creation of key

resource "aws_key_pair" "task" {
  key_name   = "mytask"
  public_key = var.x
}



// Creating own security group

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = "vpc-4ef5e826"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


// Launching EC2 instance

resource "aws_instance" "myos" {
  ami = "ami-07a8c73a650069cf3"
  instance_type = "t2.micro"
  key_name = "mytask"
  security_groups = [ "allow_tls" ]


tags = {
 Name = "mylinuxos"
  }
}

output "myos" {
  value = aws_instance.myos
}



// Creating an EBS Volume

resource "aws_ebs_volume" "pendrive" {
  availability_zone = aws_instance.myos.availability_zone
  size              = 1

  tags = {
    Name = "pendrive"
  }
}


// Attaching the EBS volume

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.pendrive.id
  instance_id = aws_instance.myos.id
}



// Creating S3 bucket

resource "aws_s3_bucket" "b" {
  bucket = "cloudtaskyash"
  acl    = "private"

  tags = {
    Name = "My bucket"
  }
}

locals {
  s3_origin_id = "myS3Origin"
}

output "b" {
  value = aws_s3_bucket.b
}



// Creating Origin Access Identity

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Some comment"
}

output "origin_access_identity" {
  value = aws_cloudfront_origin_access_identity.origin_access_identity
}


// Creating bucket policy

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.b.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.b.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.b.id
  policy = data.aws_iam_policy_document.s3_policy.json
}



// Creating CloudFront

resource "aws_cloudfront_distribution" "s3_distribution" {

  origin {
    domain_name = aws_s3_bucket.b.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true


 default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

