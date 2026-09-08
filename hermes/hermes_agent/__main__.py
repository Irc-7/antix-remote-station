#!/usr/bin/env python3
"""
Nous Research Hermes Agent - Ultra-Lightweight API Client CLI
Berjalan 100% sebagai client API eksternal untuk mesin dengan RAM terbatas (1 GB).
"""
import os
import sys
import json
from typing import List, Dict

try:
    import httpx
except ImportError:
    print("[ERROR] Modul 'httpx' belum terpasang. Jalankan pip install -r requirements.txt")
    sys.exit(1)

try:
    from rich.console import Console
    from rich.markdown import Markdown
    from rich.theme import Theme
    custom_theme = Theme({
        "info": "cyan",
        "warning": "yellow",
        "error": "bold red",
        "agent": "bold green",
        "user": "bold blue"
    })
    console = Console(theme=custom_theme)
except ImportError:
    console = None


def print_msg(role: str, text: str):
    if console:
        if role == "user":
            console.print(f"\n[user]You:[/user] {text}")
        elif role == "agent":
            console.print(f"\n[agent]Hermes:[/agent]")
            console.print(Markdown(text))
        elif role == "error":
            console.print(f"[error][ERROR][/error] {text}")
        elif role == "info":
            console.print(f"[info][INFO][/info] {text}")
    else:
        if role == "user":
            print(f"\nYou: {text}")
        elif role == "agent":
            print(f"\nHermes:\n{text}")
        else:
            print(f"[{role.upper()}] {text}")


def main():
    base_url = os.getenv("HERMES_API_BASE_URL", "https://api.nousresearch.com/v1").rstrip("/")
    api_key = os.getenv("HERMES_API_KEY", "")
    model = os.getenv("HERMES_MODEL", "Hermes-3-Llama-3.1-8B")
    temperature = float(os.getenv("HERMES_TEMPERATURE", "0.7"))
    max_tokens = int(os.getenv("HERMES_MAX_TOKENS", "2048"))
    timeout = float(os.getenv("HERMES_TIMEOUT", "60.0"))
    system_prompt = os.getenv(
        "HERMES_SYSTEM_PROMPT",
        "You are Hermes, an autonomous and concise AI engineer and assistant."
    )

    if not api_key:
        print_msg("error", "HERMES_API_KEY tidak ditemukan di environment variables.")
        sys.exit(1)

    messages: List[Dict[str, str]] = [
        {"role": "system", "content": system_prompt}
    ]

    print_msg("info", f"Terhubung ke endpoint: {base_url} (Model: {model})")
    print_msg("info", "Ketik /quit atau /exit untuk mengakhiri, /clear untuk mereset riwayat.")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    client = httpx.Client(timeout=timeout)

    while True:
        try:
            user_input = input("\nYou > ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nKeluar...")
            break

        if not user_input:
            continue

        if user_input.lower() in ["/exit", "/quit"]:
            print("Sampai jumpa.")
            break

        if user_input.lower() == "/clear":
            messages = [{"role": "system", "content": system_prompt}]
            print_msg("info", "Riwayat percakapan telah dibersihkan.")
            continue

        if user_input.lower() == "/help":
            print("\nPerintah:")
            print("  /clear  - Hapus riwayat percakapan")
            print("  /exit   - Keluar dari aplikasi")
            print("  /quit   - Keluar dari aplikasi")
            print("  /help   - Tampilkan bantuan ini")
            continue

        messages.append({"role": "user", "content": user_input})

        # Batasi riwayat percakapan agar RAM tetap hemat (maksimal 10 putaran interaksi)
        if len(messages) > 21:
            messages = [messages[0]] + messages[-20:]

        payload = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": True
        }

        endpoint = f"{base_url}/chat/completions"
        assistant_reply = []

        try:
            if console:
                console.print("\n[agent]Hermes:[/agent] ", end="")
            else:
                print("\nHermes: ", end="", flush=True)

            with client.stream("POST", endpoint, headers=headers, json=payload) as response:
                if response.status_code != 200:
                    err_body = response.read().decode("utf-8", errors="ignore")
                    print()
                    print_msg("error", f"HTTP {response.status_code}: {err_body}")
                    messages.pop()
                    continue

                for line in response.iter_lines():
                    if not line:
                        continue
                    if line.startswith("data: "):
                        data_str = line[6:].strip()
                        if data_str == "[DONE]":
                            break
                        try:
                            chunk = json.loads(data_str)
                            delta = chunk.get("choices", [{}])[0].get("delta", {})
                            content = delta.get("content", "")
                            if content:
                                assistant_reply.append(content)
                                if console:
                                    console.print(content, end="")
                                else:
                                    print(content, end="", flush=True)
                        except json.JSONDecodeError:
                            continue

            full_reply = "".join(assistant_reply)
            if console:
                console.print()
            else:
                print()
            messages.append({"role": "assistant", "content": full_reply})

        except httpx.ConnectError:
            print()
            print_msg("error", f"Gagal terhubung ke host {base_url}. Periksa koneksi internet.")
            messages.pop()
        except httpx.TimeoutException:
            print()
            print_msg("error", "Permintaan waktu habis (timeout).")
            messages.pop()
        except Exception as exc:
            print()
            print_msg("error", f"Kesalahan tidak terduga: {str(exc)}")
            messages.pop()


if __name__ == "__main__":
    main()
