"""Privacy and stale-project scanner for this static workstation companion."""
import re

PATTERNS = {
    "stale project content": r"rmdc\.|RM_REPO_CHECKOUT|priority-rm-assistant-poc|studio-onedrive|studio-mcp|CD_ENABLED|fabric-iq",
    "embedded credential": r"(?i)(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|Bearer\s+[A-Za-z0-9._-]{12,}|AccountKey\s*=\s*[A-Za-z0-9+/]{12,})",
    "personal absolute user path": r"(?i)C:[\\/]Users[\\/](?!<|\{\{)[^\\/\s<>]+",
    "email address": r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
    "concrete cloud/account GUID": r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b",
}


def scan(text):
    return [label for label, pattern in PATTERNS.items() if re.search(pattern, text)]
