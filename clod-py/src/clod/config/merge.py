"""Deep merge utility for configuration dictionaries."""

from typing import Any


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Deep merge two dictionaries.

    Merges `override` into `base` recursively. For nested dicts, the merge
    is recursive. For all other types (including lists), the override value
    replaces the base value entirely.

    Args:
        base: The base dictionary to merge into.
        override: The dictionary whose values take precedence.

    Returns:
        A new dictionary with merged values. Neither input is modified.

    Examples:
        >>> deep_merge({"a": 1}, {"b": 2})
        {'a': 1, 'b': 2}

        >>> deep_merge({"a": {"x": 1}}, {"a": {"y": 2}})
        {'a': {'x': 1, 'y': 2}}

        >>> deep_merge({"a": [1, 2]}, {"a": [3, 4]})
        {'a': [3, 4]}
    """
    result = base.copy()

    for key, override_value in override.items():
        if (
            key in result
            and isinstance(result[key], dict)
            and isinstance(override_value, dict)
        ):
            # Recursively merge nested dicts
            result[key] = deep_merge(result[key], override_value)
        else:
            # Override value (including lists - no concatenation)
            result[key] = override_value

    return result
