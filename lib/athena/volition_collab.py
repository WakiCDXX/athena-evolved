#!/usr/bin/env python3
"""Collaborate: synthesize peer responses."""
import json, os, urllib.request, urllib.error, sys

peer_outs = os.environ.get('INTROSPECTION_PEER_OUTS', '').split()
question = os.environ.get('INTROSPECTION_QUESTION', '')
task_id = os.environ.get('INTROSPECTION_TASK_ID', '')
state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')
decision_log = os.environ.get('INTROSPECTION_DECISION_LOG', '')
now_ts = os.environ.get('INTROSPECTION_NOW', '0')
url = os.environ.get('INTROSPECTION_OPENROUTER_URL', '') + '/chat/completions'
key = os.environ.get('INTROSPECTION_OPENROUTER_KEY', '')

results = []
for ref in peer_outs:
    parts = ref.split(':')
    if len(parts) >= 3:
        out_file = parts[2]
        if os.path.exists(out_file):
            data = json.load(open(out_file))
            results.append({'model': parts[1], 'response': data.get('response', ''),
                'confidence': 0.75, 'processing_time': data.get('completed', 0) - data.get('started', 0)})

consensus_header = '## Cross-Domain Synthesis\n\nQuestion: ' + question + '\n\n'
synthesis_parts = [f'### {r["model"]} ({r["confidence"]:.2f})\n{r["response"]}' for r in results]
raw_consensus = '\n\n---\n\n'.join(synthesis_parts)

try:
    req = urllib.request.Request(url, data=json.dumps({
        'model': 'nvidia/nemotron-3-ultra-550b-a55b:free',
        'messages': [
            {'role': 'system', 'content': 'You are a cross-domain synthesis engine.'},
            {'role': 'user', 'content': raw_consensus}
        ], 'temperature': 0.5, 'max_tokens': 2000
    }).encode(), headers={
        'Authorization': f'Bearer {key}', 'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/Gitlawb/openclaude', 'X-Title': 'Athena Brainstorm'
    }, method='POST')
    with urllib.request.urlopen(req, timeout=60) as resp:
        api_data = json.loads(resp.read())
        consensus = consensus_header + '\n\n' + api_data['choices'][0]['message']['content']
except Exception as e:
    consensus = consensus_header + '\n\n' + raw_consensus

calibration_entry = {
    'ts': int(now_ts), 'question': question,
    'models_used': [r['model'] for r in results], 'cross_domain': True,
    'peer_count': len(results), 'method': 'multi-model-peer-consultation'
}

doubt_path = '/opt/athena/state/doubt.json'
state = {}
try:
    with open(state_path) as f:
        state = json.load(f)
except:
    pass
entry = {'ts': int(now_ts), 'type': 'collaboration', 'question': question,
    'task_id': task_id, 'peers': results, 'consensus': consensus,
    'calibration': calibration_entry, 'method': 'multi-model-peer-consultation'}
state['last_decision'] = entry
state['last_updated'] = int(now_ts)
with open(state_path, 'w') as f:
    json.dump(state, f, separators=(',', ':'))
with open(decision_log, 'a') as f:
    f.write(json.dumps(entry) + '\n')

try:
    with open(doubt_path) as f:
        doubt = json.load(f)
    log = doubt.get('calibration_log', [])
    log.append(calibration_entry)
    doubt['calibration_log'] = log[-50:]
    doubt['last_updated'] = int(now_ts)
    with open(doubt_path, 'w') as f:
        json.dump(doubt, f, separators=(',', ':'))
except:
    pass

print(consensus)
