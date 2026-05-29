# Compliance

In order to ensure a consistent experience and long-term maintainability,
member repositories of the Storm Library for Terraform must adhere to the
following set of rules:

- `terraform.tf` must contain a `terraform {}` block

- The `required_version` of Terraform in the terraform block must be >= 1

- There must be a file called `./assets/architecture.drawio`

- There must be a file called `./README.md`. That file must contain all
  the sections in the same order that are in `./slt-repo-template`, in
  the same order. Sections are starting with "## ". The "Credits" section
  is optional.
