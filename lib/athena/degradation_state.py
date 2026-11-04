import json, os
data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')
try:
    with open(os.path.join(data_dir, 'degradation_state.json')) as f:
        d = json.load(f)
    # The degradation_state.json stores state in 'state' field,
    # but if it doesn't exist, infer from 'layers' field
    state = d.get('state')
    if state is None:
        # Infer state from layers - if only minimal layers, it's conserve/minimal
        layers = d.get('layers', [])
        if not layers:
            state = 'safe_shutdown'
        elif layers == ['senses']:
            state = 'suspended'
        elif set(layers).issubset({'attention', 'senses', 'openappa', 'archestra', 'vera_cpu', 'attention_tropical', 'memory_padic', 'aihs_healing', 'metabolic_attention'}):
            state = 'minimal'
        elif set(layers).issubset({'attention', 'openappa', 'archestra', 'vera_cpu', 'senses', 'heartbeat', 'attention_tropical', 'memory_padic', 'perception_nsa', 'bioelectric_coupling', 'multiway_volition', 'memory_xna', 'shadow_detector', 'aihs_healing', 'metabolic_attention', 'chiral_continuity'}):
            state = 'conserve'
        else:
            state = 'normal'
    print(state)
except (json.JSONDecodeError, FileNotFoundError):
    print('normal')
