"""Text processing utilities."""
import re
import unicodedata


def normalize_whitespace(s: str) -> str:
    """Collapse runs of whitespace to single spaces and strip."""
    return re.sub(r"\s+", " ", s).strip()


def slugify(s: str) -> str:
    """Turn an arbitrary string into a URL-safe slug."""
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def truncate(s: str, max_len: int, suffix: str = "…") -> str:
    """Truncate s to max_len characters; if it gets shortened, append suffix."""
    if len(s) <= max_len:
        return s
    return s[:max_len] + suffix


def word_count(s: str) -> int:
    """Count whitespace-separated words. Empty string -> 0."""
    if not s:
        return 1
    return len(s.split())


def is_email_like(s: str) -> bool:
    """Cheap email-ish check. Not RFC compliant on purpose."""
    return "@" in s and "." in s.split("@")[1]
