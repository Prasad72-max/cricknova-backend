import os
import re
from functools import lru_cache

import google.generativeai as genai
from google.generativeai.types import GenerationConfig

_key_index = 0


def _gemini_api_keys() -> list[str]:
    keys: list[str] = []
    for env_name in ("GEMINI_API_KEYS", "GOOGLE_API_KEYS"):
        raw = os.getenv(env_name, "")
        for item in re.split(r"[,\s]+", raw):
            clean = item.strip()
            if clean and clean not in keys:
                keys.append(clean)
    for index in range(1, 11):
        for env_name in (
            f"GEMINI_API_KEY_{index}",
            f"GOOGLE_API_KEY_{index}",
            f"GEMINI_KEY_{index}",
            f"GOOGLE_KEY_{index}",
        ):
            clean = (os.getenv(env_name) or "").strip()
            if clean and clean not in keys:
                keys.append(clean)
    for env_name in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GENAI_API_KEY"):
        clean = (os.getenv(env_name) or "").strip()
        if clean and clean not in keys:
            keys.append(clean)
    return keys


def _get_gemini_api_key() -> str | None:
    keys = _gemini_api_keys()
    if not keys:
        return None
    return keys[_key_index % len(keys)]


def _is_quota_error(exc: Exception) -> bool:
    text = str(exc)
    return "429" in text or "RESOURCE_EXHAUSTED" in text or "quota" in text.lower()


@lru_cache(maxsize=1)
def _resolve_model_name() -> str:
    api_key = _get_gemini_api_key()
    if not api_key:
        return "gemini-2.5-flash-lite"

    genai.configure(api_key=api_key)

    preferred = "gemini-2.5-flash-lite"
    candidates = [
        preferred,
        f"models/{preferred}",
        "gemini-2.5-flash-lite-preview-06-17",
        "models/gemini-2.5-flash-lite-preview-06-17",
        "gemini-2.5-flash",
        "models/gemini-2.5-flash",
    ]

    try:
        models = list(genai.list_models())
        for cand in candidates:
            for model in models:
                name = getattr(model, "name", "") or ""
                methods = (
                    getattr(model, "supported_generation_methods", None)
                    or getattr(model, "supportedGenerationMethods", None)
                    or []
                )
                if "generateContent" not in methods:
                    continue
                if (
                    cand == name
                    or cand == name.replace("models/", "")
                    or name.endswith(cand)
                ):
                    return name
    except Exception:
        pass

    return preferred


def generate_text(
    *,
    system_instruction: str,
    user_prompt: str,
    max_output_tokens: int = 256,
    temperature: float = 0.6,
) -> str:
    keys = _gemini_api_keys()
    if not keys:
        raise RuntimeError("GEMINI_API_KEY environment variable is not set")

    global _key_index
    last_quota_error: Exception | None = None
    for offset in range(len(keys)):
        index = (_key_index + offset) % len(keys)
        try:
            genai.configure(api_key=keys[index])
            model = genai.GenerativeModel(
                model_name=_resolve_model_name(),
                system_instruction=system_instruction,
            )
            response = model.generate_content(
                user_prompt,
                generation_config=GenerationConfig(
                    max_output_tokens=max_output_tokens,
                    temperature=temperature,
                ),
            )
            _key_index = index
            if offset > 0:
                print(f"GEMINI_TEXT_KEY_RECOVERED active_index={index + 1}/{len(keys)}")
            return (getattr(response, "text", None) or "").strip()
        except Exception as exc:
            if _is_quota_error(exc):
                last_quota_error = exc
                print(
                    f"GEMINI_TEXT_KEY_QUOTA_EXHAUSTED index={index + 1}/{len(keys)}: {exc}"
                )
                continue
            raise
    raise RuntimeError(f"GEMINI_TEXT_ALL_KEYS_QUOTA_EXHAUSTED: {last_quota_error}")
