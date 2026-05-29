# Compliance

In order to ensure a consistent experience and long-term maintainability,
member repositories of the Storm Library for Terraform must adhere to the
following set of rules:

- `terraform.tf` must contain a `terraform {}` block

- The `required_version` of Terraform in the terraform block must be >= 1

- There must be a file called `./assets/architecture.drawio`

- The `README.md` must contain all section names that are in the reference
  `README.md`, and in the same order.

- The "## Credits" section in the `README.md` is optional.

- The `.gitignore` must contain all entries that are in the reference
  `.gitignore`, but may contain more.
