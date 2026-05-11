output "rds_backup_retention_period" {
  description = "RDS automated backup retention period in days"
  value       = module.rds.backup_retention_period
}

output "rds_backup_window" {
  description = "RDS preferred backup window"
  value       = module.rds.backup_window
}

output "rds_maintenance_window" {
  description = "RDS preferred maintenance window"
  value       = module.rds.maintenance_window
}

output "rds_deletion_protection" {
  description = "Whether deletion protection is enabled for RDS"
  value       = module.rds.deletion_protection
}

output "rds_skip_final_snapshot" {
  description = "Whether RDS final snapshot is skipped on destroy"
  value       = module.rds.skip_final_snapshot
}

output "rds_copy_tags_to_snapshot" {
  description = "Whether RDS tags are copied to snapshots"
  value       = module.rds.copy_tags_to_snapshot
}
