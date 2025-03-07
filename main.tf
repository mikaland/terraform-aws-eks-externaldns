locals {
  owners      = var.office
  environment = var.environment
  name        = "${var.office}-${var.environment}"
  common_tags = {
    owners      = local.owners
    environment = local.environment
  }
}

resource "aws_iam_policy" "externaldns_iam_policy" {
  name        = "${local.name}-AllowExternalDNSUpdates"
  path        = "/"
  description = "External DNS IAM Policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:ChangeResourceRecordSets"
        ],
        "Resource" : [
          "arn:aws:route53:::hostedzone/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ],
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}

output "externaldns_iam_policy_arn" {
  value = aws_iam_policy.externaldns_iam_policy.arn
}

resource "aws_iam_role" "externaldns_iam_role" {
  name = "${local.name}-externaldns-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = "${var.aws_iam_openid_connect_provider_arn}"
        }
        Condition = {
          StringEquals = {
            "${var.aws_iam_openid_connect_provider_extract_from_arn}:aud" : "sts.amazonaws.com",
            "${var.aws_iam_openid_connect_provider_extract_from_arn}:sub" : "system:serviceaccount:default:external-dns"
          }
        }
      },
    ]
  })

  tags = {
    tag-key = "AllowExternalDNSUpdates"
  }
}

resource "aws_iam_role_policy_attachment" "externaldns_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.externaldns_iam_policy.arn
  role       = aws_iam_role.externaldns_iam_role.name
}

output "externaldns_iam_role_arn" {
  description = "External DNS IAM Role ARN"
  value       = aws_iam_role.externaldns_iam_role.arn
}

resource "helm_release" "external_dns" {
  depends_on = [aws_iam_role.externaldns_iam_role]

  name = "external-dns"

  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"

  namespace = "default"

  set {
    name  = "image.repository"
    value = "registry.k8s.io/external-dns/external-dns"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.externaldns_iam_role.arn
  }

  set {
    name  = "provider" # https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns
    value = "aws"
  }

  set {
    name  = "policy" # default is "upsert-only" https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns
    value = "sync"   # "sync" will ensure that when ingress resource is deleted, equivalent DNS record in Route53 will get deleted
  }

}
