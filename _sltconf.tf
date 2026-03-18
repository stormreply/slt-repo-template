variable "_metadata" {
  description = "Select metadata passed from GitHub Workflows"
  type = object({
    actor      = string # Github actor (deployer) of the deployment
    catalog_id = string # SLT catalog id of this module
    deployment = string # slt-<catalod_id>-<repo>-<actor>
    ref        = string # Git reference of the deployment
    ref_name   = string # Git ref_name (branch) of the deployment
    repo       = string # GitHub short repository name (without owner) of the deployment
    repository = string # GitHub full repository name (including owner) of the deployment
    sha        = string # Git (full-length, 40 char) commit SHA of the deployment
    short_name = string # slt-<catalog_id>-<actor>
    time       = string # Timestamp of the deployment
  })
  default = {
    actor      = ""
    catalog_id = ""
    deployment = ""
    ref        = ""
    ref_name   = ""
    repo       = ""
    repository = ""
    sha        = ""
    short_name = ""
    time       = ""
  }
}



locals {
  _default_tags = merge(

    {
      for key, value in var._metadata :
      "deployment-${replace(key, "_", "-")}" => value
      if value != "" && !contains(["catalog_id", "deployment", "short_name"], key)
    },

    var._metadata.ref_name != ""
    ? { deployment-code = "https://github.com/${var._metadata.repository}/tree/${var._metadata.ref_name}" }
    : {},

    var._metadata.sha != ""
    ? { deployment-commit = "https://github.com/${var._metadata.repository}/commit/${var._metadata.sha}" }
    : {},

    var._metadata.deployment != ""
    ? { deployment-name = var._metadata.deployment }
    : {},

    var._metadata.repository != ""
    ? { deployment-repository = var._metadata.repository != "" ? "https://github.com/${var._metadata.repository}" : "" }
    : {},

    var._metadata.sha != ""
    ? { deployment-sha = var._metadata.repository != "" ? substr(var._metadata.sha, 0, 7) : "" }
    : {}
  )

  _metadata = merge(
    var._metadata,
    var._metadata.deployment == "" ? { deployment = basename(abspath(path.module)) } : {},
    var._metadata.short_name == "" ? { short_name = basename(abspath(path.module)) } : {}
  )

  _deployment = local._metadata.deployment
  _name_tag   = local._metadata.deployment

  _slt_offset             = tonumber(coalesce(try(local._metadata.catalog_id, "0"), "0"))
  _slt_172_31_subnet_cidr = "172.31.${128 + local._slt_offset}.0/24"
  _slt_172_16_vpc_cidr    = "172.16.${local._slt_offset}.0/24"
}



locals {
  _slt_config = {
    default_tags         = local._default_tags
    deployment           = local._deployment
    metadata             = local._metadata
    name_tag             = local._name_tag
    assigned_subnet_cidr = local._slt_172_31_subnet_cidr
    assigned_vpc_cidr    = local._slt_172_16_vpc_cidr
  }
}



output "_slt_config" {
  description = "Map of SLT configuration"
  value       = local._slt_config
}
