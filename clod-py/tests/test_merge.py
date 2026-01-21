"""Tests for config/merge.py deep_merge function."""

import pytest

from clod.config.merge import deep_merge


class TestDeepMerge:
    """Tests for the deep_merge function."""

    def test_merge_empty_dicts(self) -> None:
        """Merging empty dicts returns empty dict."""
        assert deep_merge({}, {}) == {}

    def test_merge_empty_base(self) -> None:
        """Override values are used when base is empty."""
        assert deep_merge({}, {"a": 1, "b": 2}) == {"a": 1, "b": 2}

    def test_merge_empty_override(self) -> None:
        """Base values preserved when override is empty."""
        assert deep_merge({"a": 1, "b": 2}, {}) == {"a": 1, "b": 2}

    def test_merge_disjoint_keys(self) -> None:
        """Keys from both dicts are present."""
        result = deep_merge({"a": 1}, {"b": 2})
        assert result == {"a": 1, "b": 2}

    def test_override_simple_value(self) -> None:
        """Override value replaces base value."""
        result = deep_merge({"a": 1}, {"a": 2})
        assert result == {"a": 2}

    def test_override_type_change(self) -> None:
        """Override can change value type."""
        result = deep_merge({"a": 1}, {"a": "string"})
        assert result == {"a": "string"}

    def test_nested_dict_merge(self) -> None:
        """Nested dicts are merged recursively."""
        base = {"outer": {"a": 1, "b": 2}}
        override = {"outer": {"b": 3, "c": 4}}
        result = deep_merge(base, override)
        assert result == {"outer": {"a": 1, "b": 3, "c": 4}}

    def test_deeply_nested_merge(self) -> None:
        """Deep nesting is handled correctly."""
        base = {"l1": {"l2": {"l3": {"a": 1, "b": 2}}}}
        override = {"l1": {"l2": {"l3": {"b": 3, "c": 4}}}}
        result = deep_merge(base, override)
        assert result == {"l1": {"l2": {"l3": {"a": 1, "b": 3, "c": 4}}}}

    def test_list_replacement(self) -> None:
        """Lists are replaced entirely, not concatenated."""
        base = {"items": [1, 2, 3]}
        override = {"items": [4, 5]}
        result = deep_merge(base, override)
        assert result == {"items": [4, 5]}

    def test_list_to_dict_override(self) -> None:
        """Dict can replace a list."""
        base = {"value": [1, 2, 3]}
        override = {"value": {"a": 1}}
        result = deep_merge(base, override)
        assert result == {"value": {"a": 1}}

    def test_dict_to_list_override(self) -> None:
        """List can replace a dict."""
        base = {"value": {"a": 1}}
        override = {"value": [1, 2, 3]}
        result = deep_merge(base, override)
        assert result == {"value": [1, 2, 3]}

    def test_none_override(self) -> None:
        """None can override a value."""
        result = deep_merge({"a": 1}, {"a": None})
        assert result == {"a": None}

    def test_override_with_none_value(self) -> None:
        """None in base can be overridden."""
        result = deep_merge({"a": None}, {"a": 1})
        assert result == {"a": 1}

    def test_inputs_not_modified(self) -> None:
        """Input dicts are not modified."""
        base = {"a": 1, "nested": {"b": 2}}
        override = {"a": 2, "nested": {"c": 3}}
        base_copy = {"a": 1, "nested": {"b": 2}}
        override_copy = {"a": 2, "nested": {"c": 3}}

        deep_merge(base, override)

        assert base == base_copy
        assert override == override_copy

    def test_complex_scenario(self) -> None:
        """Complex real-world-like config merge."""
        base = {
            "sandbox_name": ".claude-sandbox",
            "enable_network": True,
            "env": {"TERM": "xterm", "LANG": "C"},
            "extra_ro": ["/usr/local"],
        }
        override = {
            "enable_network": False,
            "env": {"LANG": "en_US.UTF-8", "SHELL": "/bin/zsh"},
            "extra_ro": ["/opt/tools"],
            "new_key": "value",
        }
        result = deep_merge(base, override)

        assert result == {
            "sandbox_name": ".claude-sandbox",
            "enable_network": False,
            "env": {"TERM": "xterm", "LANG": "en_US.UTF-8", "SHELL": "/bin/zsh"},
            "extra_ro": ["/opt/tools"],
            "new_key": "value",
        }
