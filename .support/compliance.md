# Compliance

In order to ensure a consistent experience and long-term maintainability,
member repositories of the Storm Library for Terraform must adhere to the
following set of rules:

- `terraform.tf` must contain a `terraform {}` block

- The `required_version` of Terraform in the terraform block must be >= 1

- The `README.md` must preserve all text that is not between the markers
  `<!-- BEGIN_REPLACE -->` and `<!-- END_REPLACE -->` in the reference
  `README.md`

- All `<!-- BEGIN_REPLACE -->` and `<!-- END_REPLACE -->` markers in
  `README.md` must have been removed, and the text within these markers
  must have been modified

- The `README.md` must contain all section names that are in the reference
  `README.md`, and in the same order.

- The "## Credits" section in the `README.md` is optional.

- The `.gitignore` must contain all entries that are in the reference
  `.gitignore`, but may contain more.
