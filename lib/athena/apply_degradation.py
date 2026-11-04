import json, os, time

degradation_file = os.environ.get("DEGRADATION_FILE", "")
session_state_file = os.environ.get("SESSION_STATE_FILE", "")
data_dir = os.environ.get("DATA_DIR", "")

try:
    with open(degradation_file) as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    data = {}
state = data.get('state', 'normal')

try:
    with open(session_state_file) as f2:
        sess = json.load(f2)
except (json.JSONDecodeError, FileNotFoundError):
    sess = {}

configs = {
    'normal': {
        'layers': ['body', 'emotions', 'continuity', 'attention', 'introspection', 'doubt', 'volition', 'memory', 'heartbeat', 'archive', 'memory_backup', 'senses', 'attention_tropical', 'memory_padic', 'perception_nsa', 'bioelectric_coupling', 'multiway_volition', 'memory_xna', 'shadow_detector', 'aihs_healing', 'metabolic_attention', 'chiral_continuity'],
        'intervals': {'body': 300, 'emotions': 300, 'continuity': 300, 'attention': 120, 'introspection': 300, 'doubt': 300, 'volition': 300, 'memory': 300, 'heartbeat': 300, 'archive': 3600, 'memory_backup': 3600, 'senses': 120, 'attention_tropical': 300, 'memory_padic': 300, 'perception_nsa': 300, 'bioelectric_coupling': 300, 'multiway_volition': 300, 'memory_xna': 600, 'shadow_detector': 600, 'aihs_healing': 300, 'metabolic_attention': 300, 'chiral_continuity': 300},
        'capture': False, 'ocr': False, 'detector': False, 'llm': False, 'audio': False,
        'screen_state': True, 'accessibility': True, 'events': True
    },
    'conserve': {
        'layers': ['attention', 'senses', 'heartbeat', 'attention_tropical', 'memory_padic', 'aihs_healing', 'metabolic_attention'],
        'intervals': {'body': 600, 'emotions': 600, 'continuity': 600, 'attention': 300, 'introspection': 600, 'doubt': 600, 'volition': 600, 'memory': 600, 'heartbeat': 300, 'archive': 7200, 'memory_backup': 7200, 'senses': 120, 'attention_tropical': 600, 'memory_padic': 600, 'perception_nsa': 600, 'bioelectric_coupling': 600, 'multiway_volition': 600, 'memory_xna': 1200, 'shadow_detector': 1200, 'aihs_healing': 600, 'metabolic_attention': 600, 'chiral_continuity': 600},
        'capture': False, 'ocr': False, 'detector': False, 'llm': False,
        'audio': False, 'screen_state': True, 'accessibility': True, 'events': True
    },
    'minimal': {
        'layers': ['attention', 'senses', 'heartbeat', 'aihs_healing'],
        'intervals': {'body': 1200, 'emotions': 1200, 'continuity': 1200, 'attention': 600, 'introspection': 1800, 'doubt': 1800, 'volition': 1800, 'memory': 1800, 'heartbeat': 600, 'archive': 14400, 'memory_backup': 14400, 'senses': 300, 'attention_tropical': 1200, 'memory_padic': 1200, 'perception_nsa': 1200, 'bioelectric_coupling': 1200, 'multiway_volition': 1200, 'memory_xna': 2400, 'shadow_detector': 2400, 'aihs_healing': 600, 'metabolic_attention': 1200, 'chiral_continuity': 1200},
        'capture': False, 'ocr': False, 'detector': False, 'llm': False,
        'audio': False, 'screen_state': False, 'accessibility': True, 'events': True
    },
    'suspended': {
        'layers': ['senses'],
        'intervals': {'body': 0, 'emotions': 0, 'continuity': 0, 'attention': 0, 'introspection': 0, 'doubt': 0, 'volition': 0, 'memory': 0, 'heartbeat': 0, 'archive': 0, 'memory_backup': 0, 'senses': 60, 'attention_tropical': 0, 'memory_padic': 0, 'perception_nsa': 0, 'bioelectric_coupling': 0, 'multiway_volition': 0, 'memory_xna': 0, 'shadow_detector': 0, 'aihs_healing': 0, 'metabolic_attention': 0, 'chiral_continuity': 0},
        'capture': False, 'ocr': False, 'detector': False, 'llm': False,
        'audio': False, 'screen_state': False, 'accessibility': False, 'events': False
    },
    'safe_shutdown': {
        'layers': [],
        'intervals': {},
        'capture': False, 'ocr': False, 'detector': False, 'llm': False,
        'audio': False, 'screen_state': False, 'accessibility': False, 'events': False
    }
}
cfg = configs.get(state, configs['normal'])
with open(os.path.join(data_dir, "degradation_config.json"), 'w') as f:
    json.dump(cfg, f, indent=2)
print(state)
