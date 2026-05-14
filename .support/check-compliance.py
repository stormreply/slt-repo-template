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
  GITHUB_STEP_SUMMARY - wird von GitHub Actions automatisch gesetzt
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError


# Dateiendungen, die wir als Text an das Modell schicken
TEXT_EXTENSIONS = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".mjs", ".cjs",
    ".go", ".java", ".kt", ".rb", ".rs", ".php", ".cs",
    ".c", ".h", ".cpp", ".hpp",
    ".sh", ".bash", ".zsh",
    ".yml", ".yaml", ".json", ".toml", ".ini", ".cfg",
    ".md", ".rst", ".txt",
    ".tf", ".tfvars", ".hcl",
    ".sql", ".graphql", ".proto",
    ".html", ".css", ".scss",
}

EXTRA_FILENAMES = {
    "Dockerfile", "Makefile", ".gitignore", ".dockerignore",
    ".env.example", "requirements.txt", "package.json",
    "go.mod", "Cargo.toml", "pom.xml",
}

# Ordner, die wir komplett überspringen
IGNORED_DIRS = {
    ".git", ".github", "node_modules", ".venv", "venv", "env",
    "__pycache__", "dist", "build", "target", ".next", ".cache",
    "vendor", "coverage", ".idea", ".vscode",
}

# Max. Bytes Repo-Content, die wir ans Modell senden (Schutz gegen Riesen-Repos)
MAX_TOTAL_BYTES = 400_000
# Max. Bytes pro Einzeldatei
MAX_FILE_BYTES = 60_000


def collect_repo_files(root: Path) -> list[tuple[Path, str]]:
    """Sammelt textuelle Repo-Dateien bis MAX_TOTAL_BYTES."""
    collected: list[tuple[Path, str]] = []
    total = 0

    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if any(part in IGNORED_DIRS for part in path.parts):
            continue
        if path.suffix not in TEXT_EXTENSIONS and path.name not in EXTRA_FILENAMES:
            continue

        try:
            data = path.read_bytes()
        except OSError:
            continue

        if len(data) > MAX_FILE_BYTES:
            # Datei zu groß -> nur Anfang nehmen + Hinweis
            text = data[:MAX_FILE_BYTES].decode("utf-8", errors="replace")
            text += f"\n\n[... gekürzt, Originalgröße {len(data)} Bytes ...]"
        else:
            text = data.decode("utf-8", errors="replace")

        if total + len(text) > MAX_TOTAL_BYTES:
            print(
                f"::warning::Größenlimit erreicht bei {path}; "
                f"weitere Dateien werden ausgelassen.",
                file=sys.stderr,
            )
            break

        collected.append((path.relative_to(root), text))
        total += len(text)

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
        print(f"::error::Bedrock-Aufruf fehlgeschlagen: {e}", file=sys.stderr)
        raise

    content = response["output"]["message"]["content"]
    parts = [block["text"] for block in content if "text" in block]
    return "\n".join(parts).strip()


def write_step_summary(report: str) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    with open(summary_path, "a", encoding="utf-8") as f:
        f.write("# Bedrock Compliance Check\n\n")
        f.write(report)
        f.write("\n")


def main() -> int:
    region = os.environ.get("AWS_REGION")
    model_id = os.environ.get("BEDROCK_MODEL_ID")
    compliance_file = os.environ.get("COMPLIANCE_FILE", "compliance/compliance.md")

    if not region or not model_id:
        print(
            "::error::AWS_REGION und BEDROCK_MODEL_ID müssen gesetzt sein.",
            file=sys.stderr,
        )
        return 2

    compliance_path = Path(compliance_file)
    if not compliance_path.is_file():
        print(
            f"::error::Compliance-Datei nicht gefunden: {compliance_path}",
            file=sys.stderr,
        )
        return 2

    compliance_text = compliance_path.read_text(encoding="utf-8")

    repo_root = Path.cwd()
    files = collect_repo_files(repo_root)
    print(f"Sammle {len(files)} Dateien zur Prüfung ein.", file=sys.stderr)

    repo_listing = build_repo_listing(files)

    system_prompt = (
        "Du bist ein erfahrener Compliance- und Security-Auditor für "
        "Software-Repositories. Du erhältst eine Compliance-Definition in "
        "Markdown und eine Auswahl an Repo-Dateien. Prüfe systematisch jede "
        "Regel der Definition gegen den Repo-Inhalt.\n\n"
        "Antworte ausschließlich in Markdown mit folgender Struktur:\n"
        "1. Eine Zusammenfassung (1-3 Sätze).\n"
        "2. Eine Tabelle mit Spalten: Regel | Status (PASS/FAIL/UNCLEAR) | Begründung.\n"
        "3. Einen Abschnitt 'Findings' mit Details pro Verstoß: "
        "Severity (HIGH/MEDIUM/LOW), betroffene Datei(en), konkrete Empfehlung.\n"
        "4. Falls keine Verstöße gefunden wurden, mache das explizit deutlich.\n\n"
        "Sei präzise, halluziniere keine Dateinamen und zitiere nur, was "
        "tatsächlich im gelieferten Material steht.\n\n"
        "----- COMPLIANCE DEFINITION (Markdown) -----\n"
        f"{compliance_text}"
    )

    user_prompt = (
        "Bitte prüfe das folgende Repository gegen die Compliance-Definition.\n\n"
        f"{repo_listing}"
    )

    report = call_bedrock(model_id, region, system_prompt, user_prompt)

    print(report)
    write_step_summary(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())