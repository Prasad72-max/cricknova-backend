import os
from functools import lru_cache

import google.generativeai as genai
from google.generativeai.types import GenerationConfig


def _get_gemini_api_key() -> str | None:
    return (
        os.getenv("GEMINI_API_KEY")
        or os.getenv("GOOGLE_API_KEY")
        or os.getenv("GENAI_API_KEY")
    )


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
    api_key = _get_gemini_api_key()
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY environment variable is not set")

    genai.configure(api_key=api_key)
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
    return (getattr(response, "text", None) or "").strip()
