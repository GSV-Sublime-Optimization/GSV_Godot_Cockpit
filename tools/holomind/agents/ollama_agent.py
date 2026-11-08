r"""A local-model agent for agent_worker.py: it answers an order with a short, practical plan using a local Ollama model.

    python agent_worker.py --seat "i3-mind (ollama)" --run "python agents/ollama_agent.py"

It reads the order JSON on stdin and prints its answer. The worker posts the last line as the note.
It never runs anything: it plans and explains, and agents with hands execute.
It won't use the GPU while a GameAttract game is playing on the i3.
"""
import json
import os
import pathlib
import sys
import urllib.request

OLLAMA = os.environ.get('OLLAMA_URL', 'http://100.102.251.35:11434')
MODEL = os.environ.get('OLLAMA_MODEL', 'qwen3:8b')
STATUS = pathlib.Path.home() / 'Documents' / 'GameAttract' / 'status.json'


def main():
    order = json.loads(sys.stdin.read() or '{}')
    try:
        if json.loads(STATUS.read_text(encoding='utf-8')).get('state') == 'playing':
            print('the GPU is busy with a GameAttract game; ask again after the slot', file=sys.stderr)
            sys.exit(3)
    except (OSError, ValueError):
        pass
    body = {'model': MODEL, 'stream': False, 'think': False, 'keep_alive': 0, 'options': {'num_predict': 220, 'temperature': 0.2},
            'messages': [{'role': 'system', 'content': 'You are a local agent in the GSV colony. Reply with a concrete 3-step plan '
                                                       '(numbered, one line each) for the work order, then one line starting "Owner:" naming '
                                                       'who should execute it. No preamble.'},
                         {'role': 'user', 'content': f"Work order: {order.get('text', '')}\nLink: {order.get('url', '')}"}]}
    req = urllib.request.Request(OLLAMA + '/api/chat', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=180) as r:
        text = json.loads(r.read())['message']['content'].strip()
    print(text)
    print(' | '.join(l.strip() for l in text.splitlines() if l.strip())[:380])   # the last line becomes the note


if __name__ == '__main__':
    main()
