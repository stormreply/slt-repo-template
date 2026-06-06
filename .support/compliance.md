# Compliance

In order to ensure a consistent experience and long-term maintainability,
member repositories of the Storm Library for Terraform must adhere to the
following set of rules:

1. `terraform.tf` must contain a `terraform {}` block

1. The `required_version` of Terraform in the terraform block must be >= 1
1. The `README.md` must preserve all text that is not between the replace
   markers `<!-- BEGIN_REPLACE` and `END_REPLACE -->` in the reference
   `README.md`
1. All replace markers in `README.md` must have been removed, and the text
   within these markers must have been modified
1. The `README.md` must contain all section names that are in the reference
   `README.md`, and in the same order.
1. The "## Credits" section in the `README.md` is optional.
1. After the very first `# `-heading in the `README.md`, there must be a
   badge block like in the reference `README.md`
1. The `.gitignore` must contain all entries that are in the reference
   `.gitignore`, but may contain more.
