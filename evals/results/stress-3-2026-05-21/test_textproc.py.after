import pytest
from textproc import normalize_whitespace, slugify, truncate, word_count, is_email_like


def test_normalize_whitespace():
    assert normalize_whitespace("  hello   world  ") == "hello world"
    assert normalize_whitespace("a\tb\nc") == "a b c"


def test_slugify():
    assert slugify("Hello, World!") == "hello-world"
    assert slugify("café au lait") == "cafe-au-lait"


def test_truncate_no_change():
    assert truncate("short", 10) == "short"


def test_truncate_with_suffix_fits_in_limit():
    assert truncate("longish text", 8) == "longish…"


def test_word_count():
    assert word_count("") == 0
    assert word_count("one") == 1
    assert word_count("one two three") == 3
    assert word_count("  ") == 0


def test_is_email_like():
    assert is_email_like("a@b.co")
    assert not is_email_like("a@b")
    assert not is_email_like("no-at-here")
