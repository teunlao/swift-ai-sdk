#!/usr/bin/env python3
"""
Parse Codex MCP JSONL output into readable format.

Usage:
    python scripts/parse-codex-output.py /tmp/codex-interactive-output.jsonl --last 50
    python scripts/parse-codex-output.py /tmp/codex-interactive-output.jsonl --reasoning
    python scripts/parse-codex-output.py /tmp/codex-interactive-output.jsonl --commands
    python scripts/parse-codex-output.py /tmp/codex-interactive-output.jsonl --timeline
    python scripts/parse-codex-output.py /tmp/codex-interactive-output.jsonl --stuck
"""

import json
import sys
import argparse
from collections import defaultdict
from datetime import datetime

# ANSI color codes
class Colors:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    PURPLE = '\033[95m'
    CYAN = '\033[96m'
    GRAY = '\033[90m'
    BOLD = '\033[1m'
    END = '\033[0m'


def parse_jsonl(file_path, last_n=None):
    """Read JSONL file and return parsed events."""
    events = []
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()
            if last_n:
                lines = lines[-last_n:]
            for line in lines:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except FileNotFoundError:
        print(f"❌ File not found: {file_path}")
        sys.exit(1)
    return events


def merge_deltas(events):
    """Merge agent_reasoning_delta and agent_message_delta into complete messages."""
    merged = []
    current_reasoning = []
    current_message = []

    for event in events:
        msg_type = event.get('params', {}).get('msg', {}).get('type')

        if msg_type == 'agent_reasoning_delta':
            delta = event['params']['msg'].get('delta', '')
            current_reasoning.append(delta)
        elif msg_type == 'agent_reasoning':
            # Complete reasoning block
            if current_reasoning:
                merged.append({
                    'type': 'reasoning',
                    'text': ''.join(current_reasoning)
                })
                current_reasoning = []
            # Also add the complete one
            text = event['params']['msg'].get('text', '')
            if text:
                merged.append({'type': 'reasoning', 'text': text})

        elif msg_type == 'agent_message_delta':
            delta = event['params']['msg'].get('delta', '')
            current_message.append(delta)
        elif msg_type == 'agent_message':
            # Complete message
            if current_message:
                merged.append({
                    'type': 'message',
                    'text': ''.join(current_message)
                })
                current_message = []
            # Also add the complete one
            text = event['params']['msg'].get('text', '')
            if text:
                merged.append({'type': 'message', 'text': text})

        elif msg_type == 'exec_command_begin':
            cmd = event['params']['msg'].get('command', [])
            if isinstance(cmd, list):
                cmd = ' '.join(cmd)
            merged.append({'type': 'command', 'text': cmd})

        elif msg_type == 'exec_command_end':
            exit_code = event['params']['msg'].get('exit_code', 0)
            stdout = event['params']['msg'].get('stdout', '')[:200]  # First 200 chars
            if exit_code != 0:
                merged.append({'type': 'error', 'text': f"Exit code: {exit_code}"})
            elif stdout:
                merged.append({'type': 'output', 'text': stdout})

        elif msg_type == 'task_started':
            merged.append({'type': 'event', 'text': '🚀 Task started'})

        elif msg_type == 'task_complete':
            merged.append({'type': 'event', 'text': '✅ Task complete'})

        elif msg_type == 'token_count':
            info = event['params']['msg'].get('info')
            if info:
                total = info.get('total_token_usage', {})
                if total:
                    tokens = total.get('total_tokens', 0)
                    cached = total.get('cached_input_tokens', 0)
                    merged.append({
                        'type': 'tokens',
                        'text': f"Tokens: {tokens:,} (cached: {cached:,})"
                    })

    return merged


def print_readable(merged, filter_type=None, compact=False, use_colors=True):
    """Print merged events in readable format."""
    for item in merged:
        if filter_type and item['type'] != filter_type:
            continue

        text = item['text']

        if compact:
            # Compact mode: one line per event
            text_preview = text[:80] + '...' if len(text) > 80 else text
            if item['type'] == 'reasoning':
                icon = '🧠'
                color = Colors.BLUE if use_colors else ''
            elif item['type'] == 'message':
                icon = '💬'
                color = Colors.GREEN if use_colors else ''
            elif item['type'] == 'command':
                icon = '⚡'
                color = Colors.YELLOW if use_colors else ''
            elif item['type'] == 'error':
                icon = '❌'
                color = Colors.RED if use_colors else ''
            elif item['type'] == 'tokens':
                icon = '📊'
                color = Colors.CYAN if use_colors else ''
            else:
                icon = '•'
                color = Colors.GRAY if use_colors else ''

            end = Colors.END if use_colors else ''
            print(f"{icon} {color}{text_preview}{end}")
        else:
            # Full mode: with newlines and formatting
            if item['type'] == 'reasoning':
                color = Colors.BLUE if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"\n🧠 {color}{text}{end}")
            elif item['type'] == 'message':
                color = Colors.GREEN if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"\n💬 {color}{text}{end}")
            elif item['type'] == 'command':
                color = Colors.YELLOW if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"\n⚡ $ {color}{text}{end}")
            elif item['type'] == 'output':
                color = Colors.GRAY if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"   → {color}{text[:100]}...{end}")
            elif item['type'] == 'error':
                color = Colors.RED if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"\n❌ {color}{text}{end}")
            elif item['type'] == 'event':
                print(f"\n{text}")
            elif item['type'] == 'tokens':
                color = Colors.CYAN if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"\n📊 {color}{text}{end}")


def print_summary(events):
    """Print summary statistics."""
    types = defaultdict(int)
    for event in events:
        msg_type = event.get('params', {}).get('msg', {}).get('type', 'unknown')
        types[msg_type] += 1

    print("\n📈 Event Summary:")
    for msg_type, count in sorted(types.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"   {msg_type}: {count}")


def print_timeline(merged, use_colors=True):
    """Print events in timeline format with timestamps."""
    print("\n⏱️  Timeline:\n")

    start_time = None
    for item in merged:
        if 'timestamp' in item:
            ts = item['timestamp']
            if start_time is None:
                start_time = ts
            elapsed = ts - start_time
            time_str = f"+{elapsed:.1f}s"
        else:
            time_str = "     "

        text = item['text'][:60] + '...' if len(text) > 60 else item['text']

        if item['type'] == 'reasoning':
            icon = '🧠'
            color = Colors.BLUE if use_colors else ''
        elif item['type'] == 'message':
            icon = '💬'
            color = Colors.GREEN if use_colors else ''
        elif item['type'] == 'command':
            icon = '⚡'
            color = Colors.YELLOW if use_colors else ''
        elif item['type'] == 'error':
            icon = '❌'
            color = Colors.RED if use_colors else ''
        elif item['type'] == 'tokens':
            icon = '📊'
            color = Colors.CYAN if use_colors else ''
        else:
            icon = '•'
            color = Colors.GRAY if use_colors else ''

        end = Colors.END if use_colors else ''
        print(f"{time_str:>8} {icon} {color}{text}{end}")


def detect_stuck(merged, threshold_minutes=10):
    """Detect if Codex appears to be stuck."""
    reasoning_texts = [item for item in merged if item['type'] == 'reasoning']

    if len(reasoning_texts) < 5:
        return None

    # Check for repeated patterns
    last_5 = reasoning_texts[-5:]
    texts = [item['text'] for item in last_5]

    # Check if similar reasoning repeats
    similar_count = 0
    for i in range(len(texts) - 1):
        if texts[i] in texts[i+1] or texts[i+1] in texts[i]:
            similar_count += 1

    if similar_count >= 3:
        return {
            'status': 'stuck',
            'reason': 'Repeated reasoning patterns detected',
            'last_reasoning': texts[-1]
        }

    # Check for long Planning/Analyzing phase without action
    planning_keywords = ['planning', 'analyzing', 'examining', 'checking', 'investigating']
    recent_planning = sum(1 for text in texts if any(kw in text.lower() for kw in planning_keywords))

    if recent_planning >= 4:
        return {
            'status': 'possibly_stuck',
            'reason': 'Extended analysis phase without coding',
            'suggestion': 'Consider sending feedback to start coding'
        }

    return {'status': 'ok'}


def main():
    parser = argparse.ArgumentParser(description='Parse Codex MCP output')
    parser.add_argument('file', help='Path to JSONL file')
    parser.add_argument('--last', type=int, help='Show last N lines')
    parser.add_argument('--reasoning', action='store_true', help='Show only reasoning')
    parser.add_argument('--commands', action='store_true', help='Show only commands')
    parser.add_argument('--messages', action='store_true', help='Show only messages')
    parser.add_argument('--summary', action='store_true', help='Show summary only')
    parser.add_argument('--timeline', action='store_true', help='Show timeline view')
    parser.add_argument('--stuck', action='store_true', help='Detect if stuck')
    parser.add_argument('--compact', action='store_true', help='Compact one-line format')
    parser.add_argument('--no-color', action='store_true', help='Disable colors')

    args = parser.parse_args()

    use_colors = not args.no_color

    # Parse events
    events = parse_jsonl(args.file, args.last)

    if not events:
        print("❌ No events found")
        return

    color = Colors.BOLD if use_colors else ''
    end = Colors.END if use_colors else ''
    print(f"{color}📄 Total events: {len(events)}{end}")

    if args.summary:
        print_summary(events)
        return

    # Merge deltas
    merged = merge_deltas(events)

    # Stuck detection
    if args.stuck:
        result = detect_stuck(merged)
        if result:
            if result['status'] == 'stuck':
                color = Colors.RED if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"\n{color}⚠️  STUCK DETECTED{end}")
                print(f"   Reason: {result['reason']}")
                print(f"   Last: {result['last_reasoning'][:80]}...")
            elif result['status'] == 'possibly_stuck':
                color = Colors.YELLOW if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"\n{color}⏸️  POSSIBLY STUCK{end}")
                print(f"   Reason: {result['reason']}")
                print(f"   Suggestion: {result['suggestion']}")
            else:
                color = Colors.GREEN if use_colors else ''
                end = Colors.END if use_colors else ''
                print(f"\n{color}✅ Status: OK (making progress){end}")
        return

    # Timeline view
    if args.timeline:
        print_timeline(merged, use_colors)
        return

    # Filter by type
    filter_type = None
    if args.reasoning:
        filter_type = 'reasoning'
    elif args.commands:
        filter_type = 'command'
    elif args.messages:
        filter_type = 'message'

    # Print
    print_readable(merged, filter_type, compact=args.compact, use_colors=use_colors)


if __name__ == '__main__':
    main()
