provider "aws" {
  version = "~> 3.0"
  region  = var.region

  assume_role {
    role_arn = var.role_arn
  }
}

data "terraform_remote_state" "env_remote_state" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket   = var.alm_state_bucket_name
    key      = "operating-system"
    region   = "us-east-2"
    role_arn = var.alm_role_arn
  }
}

resource "random_string" "estuary_lv_salt" {
  length           = 64
  special          = true
  override_special = "/@$#*"
}

resource "local_file" "kubeconfig" {
  filename = "${path.module}/outputs/kubeconfig"
  content  = data.terraform_remote_state.env_remote_state.outputs.eks_cluster_kubeconfig
}

# Consume the actions.redirect and listen ports
resource "local_file" "helm_vars" {
  filename = "${path.module}/outputs/${terraform.workspace}.yaml"

  content = <<EOF
ingress:
  annotations:
    kubernetes.io/ingress.class: "alb"
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS-1-2-2017-01"
    alb.ingress.kubernetes.io/scheme: "${var.is_internal ? "internal" : "internet-facing"}"
    alb.ingress.kubernetes.io/subnets: "${join(
  ",",
  data.terraform_remote_state.env_remote_state.outputs.public_subnets,
)}"
    alb.ingress.kubernetes.io/security-groups: "${data.terraform_remote_state.env_remote_state.outputs.allow_all_security_group}"
    alb.ingress.kubernetes.io/certificate-arn: "${data.terraform_remote_state.env_remote_state.outputs.tls_certificate_arn}"
    alb.ingress.kubernetes.io/healthcheck-path: "/healthcheck"
    alb.ingress.kubernetes.io/tags: scos.delete.on.teardown=true
    alb.ingress.kubernetes.io/actions.redirect: '{"Type": "redirect", "RedirectConfig":{"Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
  dnsZone: "${data.terraform_remote_state.env_remote_state.outputs.internal_dns_zone_name}"
  port: 80
EOF

}

resource "null_resource" "helm_deploy" {
  provisioner "local-exec" {
    command = <<EOF
set -x

export KUBECONFIG=${local_file.kubeconfig.filename}

export AWS_DEFAULT_REGION=us-east-2

# checks to see if the secret value already exists in the environment and creates it if it doesnt
kubectl -n streaming-services get secrets -o jsonpath='{.items[*].metadata.name}' | grep estuary-lv-salt

set +x
# checks to see if the secret value already exists in the environment and creates it if it doesnt
kubectl -n streaming-services get secrets -o jsonpath='{.items[*].metadata.name}' | grep estuary-lv-salt
[ $? != 0 ] && kubectl -n streaming-services create secret generic estuary-lv-salt --from-literal=salt='${random_string.estuary_lv_salt.result}' || echo "already exists"
set -x

helm repo add scdp https://urbanos-public.github.io/charts
helm repo update
helm upgrade --install estuary scdp/estuary --namespace=streaming-services \
    --version ${var.chartVersion} \
    --values ${local_file.helm_vars.filename} \
    --values estuary.yaml \
      ${var.extraHelmCommandArgs}
EOF

  }

  triggers = {
    # Triggers a list of values that, when changed, will cause the resource to be recreated
    # ${uuid()} will always be different thus always executing above local-exec
    hack_that_always_forces_null_resources_to_execute = uuid()
  }
}

variable "chartVersion" {
  description = "Version of the chart to deploy"
  default     = "0.5.2"
}

variable "is_internal" {
  description = "Should the ALBs be internal facing"
  default     = true
}

variable "region" {
  description = "Region of ALM resources"
  default     = "us-west-2"
}

variable "role_arn" {
  description = "The ARN for the assume role for ALM access"
  default     = "arn:aws:iam::199837183662:role/jenkins_role"
}

variable "alm_role_arn" {
  description = "The ARN for the assume role for ALM access"
  default     = "arn:aws:iam::199837183662:role/jenkins_role"
}

variable "alm_state_bucket_name" {
  description = "The name of the S3 state bucket for ALM"
  default     = "scos-alm-terraform-state"
}

variable "extraHelmCommandArgs" {
  description = "Extra command arguments that will be passed to helm upgrade command"
  default     = ""
}

