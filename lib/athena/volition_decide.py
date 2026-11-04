#!/usr/bin/env python3
"""Make a decision via API."""
import json, os, urllib.request, urllib.error, sys

model = os.environ.get('INTROSPECTION_MODEL_PROVIDER2', '')
url = os.environ.get('INTROSPECTION_OPENROUTER_URL', '') + '/chat/completions'
key = os.environ.get('INTROSPECTION_OPENROUTER_KEY', '')
question = os.environ.get('INTROSPECTION_QUESTION2', '')
decision_text = os.environ.get('INTROSPECTION_DECISION', '')
state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')
decision_log = os.environ.get('INTROSPECTION_DECISION_LOG', '')
now_ts = os.environ.get('INTROSPECTION_NOW', '0')

if not model:
    print(decision_text or 'Decision: ' + question)
    sys.exit(0)

try:
    req = urllib.request.Request(url, data=json.dumps({
        'model': model, 'messages': [
            {'role': 'system', 'content': 'You are Athena\'s decision engine.'},
            {'role': 'user', 'content': question}
        ], 'temperature': 0.6, 'max_tokens': 1500
    }).encode(), headers={
        'Authorization': f'Bearer {key}', 'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/Gitlawb/openclaude', 'X-Title': 'Athena Volition'
    }, method='POST')
    with urllib.request.urlopen(req, timeout=60) as resp:
        api_data = json.loads(resp.read())
        decision_text = api_data['choices'][0]['message']['content']
    confidence = 0.85
    api_used = True
except Exception as e:
    decision_text = f'Decision: {question} — Fallback.'
    confidence = 0.5
    api_used = False

entry = {
    'ts': int(now_ts), 'type': 'decision', 'question': question,
    'model': model, 'decision': decision_text,
    'confidence': confidence, 'method': 'single-model-api' if api_used else 'fallback',
    'api_used': api_used
}

try:
    with open(decision_log, 'a') as f:
        f.write(json.dumps(entry) + '\n')
    state = {}
    try:
        with open(state_path) as f:
            state = json.load(f)
    except:
        pass
    state['last_decision'] = entry
    state['last_updated'] = int(now_ts)
    with open(state_path, 'w') as f:
        json.dump(state, f, separators=(',', ':'))
except:
    pass

print(decision_text)
