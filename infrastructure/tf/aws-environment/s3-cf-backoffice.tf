resource "aws_s3_bucket" "backoffice" {
  # Our bucket's name is going to be the same as our site's domain name.
  bucket = var.backoffice_domain_name
  # Because we want our site to be available on the internet, we set this so
  # anyone can read this bucket.
  acl    = "public-read"
  # We also need to create a policy that allows anyone to view the content.
  # This is basically duplicating what we did in the ACL but it's required by
  # AWS. This post: http://amzn.to/2Fa04ul explains why.
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${var.backoffice_domain_name}/*"]
    }
  ]
}
POLICY

  # S3 understands what it means to host a website.
  website {
    # Here we tell S3 what to use when a request comes in to the root
    # ex. https://www.example.io
    index_document = "index.html"
    # The page to serve up if a request results in an error or a non-existing
    # page.
    error_document = "404.html"
  }
}

resource "aws_cloudfront_distribution" "backoffice_distribution" {
  # origin is where CloudFront gets its content from.
  origin {
    # We need to set up a "custom" origin because otherwise CloudFront won't
    # redirect traffic from the root domain to the www domain, that is from
    # example.io to www.example.io.
    custom_origin_config {
      # These are all the defaults.
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }

    # Here we're using our S3 bucket's URL!
    domain_name = aws_s3_bucket.backoffice.website_endpoint
    # This can be any name to identify this origin.
    origin_id   = var.backoffice_domain_name
  }

  enabled             = true
  default_root_object = "index.html"

  # All values are defaults from the AWS console.
  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    # This needs to match the `origin_id` above.
    target_origin_id       = var.backoffice_domain_name
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_caching_min_ttl = 300
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  # Here we're ensuring we can hit this distribution using www.example.io
  # rather than the domain name CloudFront gives us.
  aliases = [var.backoffice_domain_name]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Here's where our certificate is loaded in
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cf_root.arn
    ssl_support_method  = "sni-only"
  }

  depends_on = [aws_acm_certificate_validation.root_certificate_validation]
}