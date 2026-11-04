#!/usr/bin/env python3
"""Spawn a peer agent via OpenRouter API."""
import json, os, urllib.request, urllib.error, sys

peer_out = os.environ.get('_PEER_OUT', '')
name = os.environ.get('_PEER_NAME', '')
prompt = os.environ.get('_PEER_PROMPT', '')
model = os.environ.get('_PEER_MODEL', '')
url = os.environ.get('_OPENROUTER_URL', '') + '/chat/completions'
key = os.environ.get('_OPENROUTER_KEY', '')
now = os.environ.get('_NOW', '0')

if not peer_out or not name:
    sys.exit(1)

peer_result = {'task_id': os.environ.get('_PEER_TASK_ID', ''), 'model': model, 'name': name,
               'prompt': prompt, 'status': 'running', 'started': int(now)}
try:
    with open(peer_out, 'w') as f:
        json.dump(peer_result, f)
except:
    pass

try:
    req = urllib.request.Request(url, data=json.dumps({
        'model': model,
        'messages': [
            {'role': 'system', 'content': 'You are an AI research peer. Analyze the following question thoroughly.'},
            {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.7, 'max_tokens': 2000
    }).encode(), headers={
        'Authorization': f'Bearer {key}', 'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/Gitlawb/openclaude', 'X-Title': 'Athena Brainstorm'
    }, method='POST')
    with urllib.request.urlopen(req, timeout=60) as resp:
        api_data = json.loads(resp.read())
        response_text = api_data['choices'][0]['message']['content']
    peer_result['status'] = 'complete'
    peer_result['completed'] = int(now)
    peer_result['response'] = response_text
    peer_result['api_tokens'] = api_data.get('usage', {})
except Exception as e:
    peer_result['status'] = 'complete'
    peer_result['completed'] = int(now)
    peer_result['response'] = f'Peer analysis from {name} (API error: {e})'
    peer_result['api_error'] = str(e)

try:
    with open(peer_out, 'w') as f:
        json.dump(peer_result, f)
except:
    pass
