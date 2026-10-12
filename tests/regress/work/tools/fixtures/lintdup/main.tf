resource "aws_s3_bucket" "b" {
  bucket = "x"
}

resource "null_resource" "x" {
  triggers = { a = "b" }
}
