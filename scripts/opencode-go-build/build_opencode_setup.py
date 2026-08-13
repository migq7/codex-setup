#!/usr/bin/env python3
"""Build scripts/codex-opencode-go-setup.sh from template.sh + model metadata."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "codex-opencode-go-setup.sh"

# Pull the current Codex base instructions from the user's working catalog
# (identical to the prompt bundled with Codex 0.147.0).
with open(Path.home() / ".codex" / "models.json", encoding="utf-8") as f:
    prompt = json.load(f)["models"][0]["base_instructions"]

# slug, display name, context window, default effort, supported efforts, description
MODELS = [
    ("deepseek-v4-flash", "DeepSeek V4 Flash", 1048576, "high", ["low", "high", "max"],
     "DeepSeek V4 Flash — 日常编码默认，OpenCode Go 原生支持 Responses API"),
    ("deepseek-v4-pro", "DeepSeek V4 Pro", 1048576, "high", ["high", "max"],
     "DeepSeek V4 Pro — 复杂推理；注意 /v1/responses 多轮与工具调用目前可能 400"),
    ("gpt-5.6-luna", "GPT-5.6 Luna", 1050000, "medium", ["low", "medium", "high", "xhigh"],
     "GPT-5.6 Luna — 原生 Responses 模型"),
    ("kimi-k2.7-code", "Kimi K2.7 Code", 262144, "high", ["high"],
     "Kimi K2.7 Code — 编码优化模型"),
    ("kimi-k3", "Kimi K3", 1048576, "max", ["max"],
     "Kimi K3 — 通用旗舰模型"),
    ("glm-5.2", "GLM-5.2", 1000000, "high", ["high", "max"],
     "GLM-5.2 — 通用旗舰，1M 上下文"),
    ("glm-5.1", "GLM-5.1", 202752, "high", ["high"],
     "GLM-5.1 — 通用模型"),
    ("grok-4.5", "Grok 4.5", 500000, "high", ["low", "medium", "high"],
     "Grok 4.5 — 通用旗舰模型"),
    ("hy3", "Hy3", 256000, "high", ["low", "high"],
     "Hy3 — 轻量高效模型"),
    ("mimo-v2.5", "MiMo V2.5", 1000000, "high", ["high"],
     "MiMo V2.5 — 高性价比模型"),
    ("mimo-v2.5-pro", "MiMo V2.5 Pro", 1048576, "high", ["high"],
     "MiMo V2.5 Pro — 高性价比进阶模型"),
    ("kimi-k2.6", "Kimi K2.6", 262144, "high", ["high"],
     "Kimi K2.6 — 通用模型"),
]

LEVEL_DESC = {
    "low": "Fast responses with lighter reasoning",
    "medium": "Balances speed and reasoning depth for everyday tasks",
    "high": "Extra high reasoning depth for complex problems",
    "max": "Maximum reasoning depth for the hardest problems",
    "xhigh": "Extra high reasoning for the most demanding problems",
}


def entry(slug, display, ctx, default_effort, efforts, desc):
    return {
        "slug": slug,
        "prefer_websockets": False,
        "support_verbosity": True,
        "default_verbosity": "low",
        "apply_patch_tool_type": "freeform",
        "web_search_tool_type": "text",
        "input_modalities": ["text"],
        "supports_image_detail_original": False,
        "truncation_policy": {"mode": "tokens", "limit": 10000},
        "supports_parallel_tool_calls": True,
        "tool_mode": None,
        "multi_agent_version": "v2",
        "use_responses_lite": False,
        "include_skills_usage_instructions": False,
        "auto_review_model_override": None,
        "context_window": ctx,
        "max_context_window": ctx,
        "effective_context_window_percent": 95,
        "auto_compact_token_limit": None,
        "comp_hash": "3000",
        "reasoning_summary_format": "experimental",
        "default_reasoning_summary": "none",
        "display_name": f"{display} (OpenCode Go)",
        "description": desc,
        "default_reasoning_level": default_effort,
        "supported_reasoning_levels": [
            {"effort": e, "description": LEVEL_DESC.get(e, "Reasoning level")} for e in efforts
        ],
        "shell_type": "shell_command",
        "visibility": "list",
        "minimal_client_version": "0.144.0",
        "supported_in_api": True,
        "availability_nux": None,
        "upgrade": None,
        "priority": 1,
        "experimental_supported_tools": [],
        "supports_search_tool": True,
        "default_service_tier": None,
        "supports_reasoning_summaries": True,
        "base_instructions": prompt,
    }


def main():
    catalog = {"models": [entry(*m) for m in MODELS]}
    json_text = json.dumps(catalog, ensure_ascii=False, indent=2)
    heredoc = f"cat > \"$TMP_MODELS\" <<'CODEX_MODELS_JSON'\n{json_text}\nCODEX_MODELS_JSON"

    template = (ROOT / "template.sh").read_text(encoding="utf-8")
    assert "__MODELS_JSON__" in template, "missing placeholder"
    final = template.replace("__MODELS_JSON__", heredoc)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(final, encoding="utf-8")
    OUT.chmod(0o755)
    print(f"wrote {OUT} ({len(final)} bytes, {final.count(chr(10))} lines)")


if __name__ == "__main__":
    main()
