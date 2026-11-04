#!/usr/bin/env python3
"""Make decision via Jev/TypeSafe AI."""
import json, os, urllib.request, urllib.error, sys

url = os.environ.get('INTROSPECTION_TYPESAFE_BASE', '') + '/systemone'
key = os.environ.get('INTROSPECTION_TYPESAFE_KEY', '')
question = os.environ.get('INTROSPECTION_QUESTION_JEV2', '')
state_path = os.environ.get('INTROSPECTION_STATE_JEV', '')
decision_log = os.environ.get('INTROSPECTION_DECISION_LOG_JEV', '')
now_ts = os.environ.get('INTROSPECTION_NOW_JEV', '0')

if not key:
    # Fallback to OpenRouter Jev
    or_url = os.environ.get('INTROSPECTION_OPENROUTER_URL', '') + '/chat/completions'
    or_key = os.environ.get('INTROSPECTION_OPENROUTER_KEY', '')
    try:
        req = urllib.request.Request(or_url, data=json.dumps({
            'model': 'typesafe/jev-latest', 'messages': [
                {'role': 'system', 'content': 'You are Jev by TypeSafe AI.'},
                {'role': 'user', 'content': question}
            ], 'temperature': 0.4, 'max_tokens': 1000
        }).encode(), headers={
            'Authorization': f'Bearer {or_key}', 'Content-Type': 'application/json',
            'HTTP-Referer': 'https://github.com/Gitlawb/openclaude', 'X-Title': 'Athena Volition'
        }, method='POST')
        with urllib.request.urlopen(req, timeout=60) as resp:
            api_data = json.loads(resp.read())
            response_text = api_data['choices'][0]['message']['content']
        method = 'jev-fallback'
    except Exception as e2:
        response_text = f'Jev fallback failed: {e2}'
        method = 'jev-fallback'
else:
    try:
        req = urllib.request.Request(url, data=json.dumps({
            'state': {}, 'questions': [{'id': 'volition-decision', 'text': question, 'type': 'decision'}]
        }).encode(), headers={
            'Authorization': f'Bearer {key}', 'Content-Type': 'application/json',
            'HTTP-Referer': 'https://github.com/Gitlawb/openclaude', 'X-Title': 'Athena Volition-Jev'
        }, method='POST')
        with urllib.request.urlopen(req, timeout=60) as resp:
            api_data = json.loads(resp.read())
            response_text = json.dumps(api_data, indent=2)
        method = 'jev-typed-decision'
    except Exception as e:
        response_text = f'Jev API error ({e})'
        method = 'jev-fallback'

entry = {
    'ts': int(now_ts), 'type': 'jev-decision', 'question': question,
    'model': 'jev', 'decision': response_text,
    'confidence': 0.95, 'method': method, 'api_used': method != 'jev-fallback'
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
    state['jev_used'] = True
    with open(state_path, 'w') as f:
        json.dump(state, f, separators=(',', ':'))
except:
    pass

print(response_text)
