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
}

output "_default_tags" {
  value = local._default_tags
}
