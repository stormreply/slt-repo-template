"""
Bedrock-basierter Compliance-Check.

Liest eine Markdown-Datei mit Compliance-Regeln, sammelt relevante Dateien
aus dem aktuellen Repo, schickt beides an AWS Bedrock (Claude auf Bedrock)
und schreibt das Ergebnis in den GitHub Step Summary.

Konfiguration via Environment-Variablen:
  AWS_REGION         - AWS-Region in der Bedrock aktiviert ist (z.B. us-east-1)
  BEDROCK_MODEL_ID   - Bedrock Model-ID bzw. Inference-Profile-ID
                       (z.B. us.anthropic.claude-sonnet-4-6-YYYYMMDD-v1:0)
  COMPLIANCE_FILE    - Pfad zur Compliance-Markdown-Datei (Default: compliance/compliance.md)
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError


INCLUDED_FILES = [
    ".github/workflows/apply.yaml",
    ".github/workflows/destroy.yaml",
    ".github/workflows/plan.yaml",
    ".github/workflows/test.yaml",
    ".gitignore",
    ".pre-commit-config.yaml",
    ".support/check-commit.sh",
    # ".support/check-compliance.py",
    ".support/check-files.sh",
    # ".support/compliance.md",
    ".support/finish-pre-commit.sh",
    ".support/prepare-pre-commit.sh",
    "assets/architecture.drawio",
    "_sltconf.tf",
    "providers.tf",
    "README.md",
    "terraform.tf",
]

MAX_FILE_BYTES = 60_000


def collect_repo_files(root: Path) -> list[tuple[Path, str]]:
    collected: list[tuple[Path, str]] = []

    for rel in INCLUDED_FILES:
        path = root / rel
        try:
            data = path.read_bytes()
        except OSError:
            print(f"::warning::Datei nicht gefunden oder nicht lesbar: {rel}", file=sys.stderr)
            continue

        if len(data) > MAX_FILE_BYTES:
            text = data[:MAX_FILE_BYTES].decode("utf-8", errors="replace")
            text += f"\n\n[... gekürzt, Originalgröße {len(data)} Bytes ...]"
        else:
            text = data.decode("utf-8", errors="replace")

        collected.append((Path(rel), text))

    return collected


def build_repo_listing(files: list[tuple[Path, str]]) -> str:
    chunks = []
    for rel_path, text in files:
        chunks.append(f"--- FILE: {rel_path} ---\n{text}")
    return "\n\n".join(chunks)


def call_bedrock(model_id: str, region: str, system_prompt: str, user_prompt: str) -> str:
    client = boto3.client("bedrock-runtime", region_name=region)
    try:
        response = client.converse(
            modelId=model_id,
            system=[{"text": system_prompt}],
            messages=[{"role": "user", "content": [{"text": user_prompt}]}],
            inferenceConfig={"maxTokens": 8000, "temperature": 0},
        )
    except ClientError as e:
        print(f"::error::Bedrock-call failed: {e}", file=sys.stderr)
        raise

    content = response["output"]["message"]["content"]
    parts = [block["text"] for block in content if "text" in block]
    return "\n".join(parts).strip()


def write_step_summary(report: str) -> int:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return 2
    with open(summary_path, "a", encoding="utf-8") as f:
        if report:
            f.write("> [!CAUTION]\n")
            f.write("> Issues have been found during compliance check. Check below:\n")
            f.write(report)
            return 1
        else:
            f.write("No compliance issues found.")
            return 0


def main() -> int:
    region = os.environ.get("AWS_REGION")
    model_id = os.environ.get("BEDROCK_MODEL_ID")
    compliance_file = os.environ.get("COMPLIANCE_FILE", "slt-repo-template/.support/compliance.md")

    if not region or not model_id:
        print(
            "::error::AWS_REGION und BEDROCK_MODEL_ID müssen gesetzt sein.",
            file=sys.stderr,
        )
        return 2

    compliance_path = Path(compliance_file)
    if not compliance_path.is_file():
        print(
            f"::error::Compliance-file not found: {compliance_path}",
            file=sys.stderr,
        )
        return 2

    compliance_text = compliance_path.read_text(encoding="utf-8")

    repo_root = Path.cwd()
    files = collect_repo_files(repo_root)
    print(f"Collecting {len(files)} files for compliance check.", file=sys.stderr)

    repo_listing = build_repo_listing(files)

    system_prompt = f"""
        You need to check a list of files from a repository for compliance.
        Compliance will be defined in a list of requirements in a markdown
        document. Check each requirement with the list of files. As a result
        of the check, return a markdown document with the following
        specification:

        1. If a compliance requirement can not be met, add a list item
           to the markdown document.

        2. Every list item must be of the following form:

           <requirement>:
             - <finding>

           where <requirement> is the wording of the requirement as defined in
           the list of requirements, and <finding> is a concise description
           of the found violation of the requirement. Where possible, include
           a filename and a line number in the finding. If multiple findings
           have been found for a single requirement, list them all underneath
           that very requirement.

        3. If compliance issues have been found, return the list as outlined
           above as a markdown document in a single string.

        4. If no issues have been found at all, return "No issues found".

        5. Do not add anything else to the markdown document, just the list
           as a single string. Especially, do not add any summary or any
           comment that all requirements have been met.

        The markdown document containing the compliance requirements is
        attached below:

        {compliance_text}
    """

    user_prompt = f"""
        Please check the following files against the compliance definition:

        {repo_listing}
    """

    # print(system_prompt)
    # print(user_prompt)

    report = call_bedrock(model_id, region, system_prompt, user_prompt)

    print(report)

    return(write_step_summary(report))


if __name__ == "__main__":
    sys.exit(main())