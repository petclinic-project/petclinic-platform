output "eso_role_arn" {
  description = "IRSA role ARN for External Secrets Operator — TEAM-2 annotates the external-secrets-sa ServiceAccount with this value"
  value       = aws_iam_role.eso.arn
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller — TEAM-2 annotates the aws-load-balancer-controller ServiceAccount with this value"
  value       = aws_iam_role.lb_controller.arn
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for EBS CSI Driver — applied to the ebs-csi-controller-sa ServiceAccount"
  value       = aws_iam_role.ebs_csi.arn
}

output "github_actions_role_arn" {
  description = "OIDC role ARN for GitHub Actions — TEAM-3 sets this as AWS_ROLE_ARN in GitHub repository secrets"
  value       = aws_iam_role.github_actions.arn
}
