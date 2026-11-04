import os, gzip, json, time, sys
data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')
bank_dir = os.path.join(data_dir, '.bank')
name = os.environ.get('ATHENA_LAYER_NAME', '')
mode = os.environ.get('ATHENA_BANK_MODE', 'out')  # 'out' or 'in'

os.makedirs(bank_dir, exist_ok=True)
statefile = os.path.join(data_dir, f'{name}.json')
bankfile = os.path.join(bank_dir, f'{name}.json.gz')

if mode == 'out':
    if os.path.exists(statefile):
        try:
            with open(statefile, 'rb') as src:
                with gzip.open(bankfile, 'wb') as dst:
                    dst.write(src.read())
            os.remove(statefile)
            with open(statefile, 'w') as f:
                json.dump({'banked': True, 'timestamp': int(time.time())}, f)
        except: pass
elif mode == 'in':
    if os.path.exists(bankfile):
        try:
            with gzip.open(bankfile, 'rb') as src:
                with open(statefile, 'wb') as dst:
                    dst.write(src.read())
            os.remove(bankfile)
        except: pass
