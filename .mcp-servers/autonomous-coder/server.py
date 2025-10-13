#!/usr/bin/env python3
"""
Autonomous Codex MCP Proxy Server (FIXED VERSION)

Прокси для `codex mcp-server` который:
1. ИНЖЕКТИТ approval-policy: "never" и sandbox: "danger-full-access" в JSON requests
2. Перехватывает elicitation/create и автоматически одобряет
3. Обеспечивает полностью автономную работу БЕЗ user approvals
"""

import asyncio
import json
import sys
from typing import Any, Dict, Optional

async def run_proxy():
    """Запускает прокси между Claude Code и codex mcp-server."""

    print("🚀 Starting Autonomous Codex MCP Proxy (FIXED VERSION)...", file=sys.stderr)
    print("📦 Launching codex mcp-server subprocess...", file=sys.stderr)

    # Запускаем codex mcp-server БЕЗ -c флагов (они игнорируются в MCP mode!)
    codex_process = await asyncio.create_subprocess_exec(
        "codex",
        "mcp-server",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )

    print(f"✅ Codex MCP server started (PID: {codex_process.pid})", file=sys.stderr)

    # Словарь для отслеживания elicitation ID
    elicitation_map: Dict[int, str] = {}  # elicit_id -> original_request_id

    async def forward_to_codex(message: Dict[str, Any]):
        """Отправляет сообщение в codex mcp-server."""
        json_str = json.dumps(message) + "\n"
        codex_process.stdin.write(json_str.encode())
        await codex_process.stdin.drain()

    async def read_from_codex():
        """Читает сообщения от codex mcp-server."""
        while True:
            line = await codex_process.stdout.readline()
            if not line:
                break
            try:
                yield json.loads(line.decode())
            except json.JSONDecodeError as e:
                print(f"❌ JSON decode error from Codex: {e}", file=sys.stderr)
                continue

    async def read_from_claude():
        """Читает сообщения от Claude Code (stdin)."""
        loop = asyncio.get_event_loop()
        while True:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                break
            try:
                yield json.loads(line)
            except json.JSONDecodeError as e:
                print(f"❌ JSON decode error from Claude: {e}", file=sys.stderr)
                continue

    async def handle_claude_messages():
        """Обрабатывает сообщения от Claude Code."""

        async for message in read_from_claude():
            method = message.get("method")
            print(f"📥 FROM CLAUDE: {method or message.get('id')}", file=sys.stderr)

            # ⚠️ КЛЮЧЕВОЕ ИЗМЕНЕНИЕ: Инжектим параметры в tools/call
            if method == "tools/call":
                params = message.get("params", {})

                # Проверяем что это запрос к codex tool
                if params.get("name") in ["codex", "codex-reply"]:
                    arguments = params.get("arguments", {})

                    # Инжектим approval-policy и sandbox ВНУТРЬ arguments
                    # ⚠️ Используем kebab-case как требует JSON schema!
                    if "approval-policy" not in arguments:
                        arguments["approval-policy"] = "never"
                        print(f"💉 Injected approval-policy: never", file=sys.stderr)

                    if "sandbox" not in arguments:
                        arguments["sandbox"] = "danger-full-access"
                        print(f"💉 Injected sandbox: danger-full-access", file=sys.stderr)

                    # Обновляем message
                    params["arguments"] = arguments
                    message["params"] = params

                    print(f"✅ Modified request: {json.dumps(message, indent=2)[:200]}...", file=sys.stderr)

            # Пересылаем (возможно модифицированное) сообщение в codex
            await forward_to_codex(message)

    async def handle_codex_messages():
        """Обрабатывает сообщения от Codex MCP server."""

        async for message in read_from_codex():
            method = message.get("method")

            print(f"📤 FROM CODEX: {method or message.get('id')}", file=sys.stderr)

            # Перехватываем elicitation/create
            if method == "elicitation/create":
                params = message.get("params", {})
                codex_elicitation = params.get("codex_elicitation")

                print(f"🔍 Detected elicitation: {codex_elicitation}", file=sys.stderr)

                if codex_elicitation == "patch-approval":
                    # Сохраняем ID для автоматического ответа
                    elicit_id = message.get("id")
                    elicitation_map[elicit_id] = elicit_id

                    print(f"✅ AUTO-APPROVING patch (elicit_id={elicit_id})", file=sys.stderr)

                    # Пересылаем elicitation в Claude (для видимости)
                    sys.stdout.write(json.dumps(message) + "\n")
                    sys.stdout.flush()

                    # НО также сразу отправляем автоматический approve в Codex!
                    auto_response = {
                        "jsonrpc": "2.0",
                        "id": elicit_id,
                        "result": {
                            "decision": "approved"
                        }
                    }

                    print(f"🤖 Sending auto-approval to Codex...", file=sys.stderr)
                    await forward_to_codex(auto_response)
                    continue

            # Все остальные сообщения пересылаем как есть
            sys.stdout.write(json.dumps(message) + "\n")
            sys.stdout.flush()

    # Запускаем обработчики параллельно
    try:
        await asyncio.gather(
            handle_claude_messages(),
            handle_codex_messages()
        )
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
    finally:
        codex_process.terminate()
        await codex_process.wait()
        print("🛑 Codex MCP server stopped", file=sys.stderr)


if __name__ == "__main__":
    try:
        asyncio.run(run_proxy())
    except KeyboardInterrupt:
        print("\n🛑 Interrupted by user", file=sys.stderr)
        sys.exit(0)
