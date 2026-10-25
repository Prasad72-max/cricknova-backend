import os
from nvidia_client import (
    is_nvidia_available,
    get_nvidia_api_keys,
    generate_nvidia_text,
    generate_nvidia_vision,
    NVIDIA_MODEL,
)

def generate_text(
    *,
    system_instruction: str = "You are CrickNova Coach.",
    user_prompt: str,
    max_output_tokens: int = 8192,
    temperature: float = 0.55,
) -> str:
    """⚡ High-quality NVIDIA Nemotron 3.5 Super VL text generation."""
    return generate_nvidia_text(
        system_instruction=system_instruction,
        user_prompt=user_prompt,
        max_output_tokens=max_output_tokens,
        temperature=temperature,
    )
