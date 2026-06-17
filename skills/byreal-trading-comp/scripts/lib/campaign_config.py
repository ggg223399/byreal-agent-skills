from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


class ConfigError(ValueError):
    pass


def default_config_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "config" / "campaigns"


def config_dir_from_env() -> Path:
    raw = os.environ.get("BYREAL_CAMPAIGN_CONFIG_DIR", "").strip()
    return Path(raw).expanduser() if raw else default_config_dir()


def normalize_path(path: str | Path) -> Path:
    return Path(path).expanduser().resolve()


def list_config_paths(config_dir: str | Path | None = None) -> list[Path]:
    root = normalize_path(config_dir or config_dir_from_env())
    if not root.is_dir():
        raise ConfigError(f"config_dir_missing:{root}")
    return sorted(root.glob("*.json"))


def load_json(path: str | Path) -> dict[str, Any]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ConfigError("config must be a JSON object")
    return data


def find_config(target: str, config_dir: str | Path | None = None) -> tuple[Path, dict[str, Any]]:
    target = (target or "").strip()
    if not target:
        raise ConfigError("campaign_required")

    raw = Path(target).expanduser()
    looks_like_path = raw.suffix == ".json" or "/" in target or "\\" in target
    if looks_like_path:
        path = normalize_path(raw)
    else:
        root = normalize_path(config_dir or config_dir_from_env())
        if not root.is_dir():
            raise ConfigError(f"config_dir_missing:{root}")
        path = normalize_path(root / f"{target}.json")

    if not path.is_file():
        raise ConfigError(f"config_missing:{path}")

    config = load_json(path)
    validate_config(config, path)
    return path, config


def _required_str(obj: dict[str, Any], key: str, where: str, errors: list[str]) -> str | None:
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{where}.{key} must be a non-empty string")
        return None
    return value


def validate_config(config: dict[str, Any], path: str | Path | None = None) -> None:
    errors: list[str] = []

    campaign_type = _required_str(config, "campaign_type", "$", errors)
    if path is not None and campaign_type:
        basename = Path(path).stem
        if campaign_type != basename:
            errors.append(f"$.campaign_type must equal file basename '{basename}'")

    display = config.get("display")
    if not isinstance(display, dict):
        errors.append("$.display must be an object")
    else:
        for key in ("title", "summary", "reward_pool_text", "link"):
            _required_str(display, key, "$.display", errors)

    eligible = config.get("eligible_pools")
    if not isinstance(eligible, list) or not eligible:
        errors.append("$.eligible_pools must be a non-empty array")
    else:
        seen_names: set[str] = set()
        seen_pairs: set[tuple[str, str]] = set()
        for idx, pool in enumerate(eligible):
            where = f"$.eligible_pools[{idx}]"
            if not isinstance(pool, dict):
                errors.append(f"{where} must be an object")
                continue
            name = _required_str(pool, "name", where, errors)
            if name:
                if name in seen_names:
                    errors.append(f"{where}.name duplicates '{name}'")
                seen_names.add(name)

            mints = pool.get("mints")
            if (
                not isinstance(mints, list)
                or len(mints) != 2
                or not all(isinstance(m, str) and m.strip() for m in mints)
            ):
                errors.append(f"{where}.mints must be two non-empty mint strings")
                continue
            if mints[0] == mints[1]:
                errors.append(f"{where}.mints must contain two distinct mints")
            pair = tuple(sorted(mints))
            if pair in seen_pairs:
                errors.append(f"{where}.mints duplicates another eligible pair")
            seen_pairs.add(pair)

    docs = config.get("docs")
    if docs is not None:
        if not isinstance(docs, dict):
            errors.append("$.docs must be an object when present")
        else:
            for key, value in docs.items():
                if not isinstance(key, str) or not isinstance(value, str) or not value.strip():
                    errors.append("$.docs values must be non-empty strings")
                    break

    rules = config.get("rules")
    if rules is not None and not isinstance(rules, dict):
        errors.append("$.rules must be an object when present")

    if errors:
        raise ConfigError("; ".join(errors))


def summarize_config(path: Path, config: dict[str, Any]) -> dict[str, Any]:
    return {
        "path": str(path),
        "campaign_type": config["campaign_type"],
        "eligible_pool_names": [p["name"] for p in config.get("eligible_pools", [])],
        "display": config.get("display"),
        "notes": config.get("notes"),
    }
