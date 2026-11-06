"""Exact per-variant CP3 CHECK contract; missing/duplicate evidence blocks."""
VARIANTS = {'cp1gap':{'bottomPatch':5},'fullscreen': {'back':5,'locked':5}, 'theme':{'switch':10},
            'headers':{'quality':5,'thumb':5,'prefetch':5},
            'feedplayer':{'controller':5,'autoPause':5,'failure':5},
            'c04chrome':{'hide':5,'drag':5,'style':5,'hud':5}}
FIELDS = {'cp1gap':{'before','after','observed'},'fullscreen':{'before','after','host'},'theme':{'before','after','sessionBefore','sessionAfter','styleObserved'},
          'headers':{'positive','negative','requests'},'feedplayer':{'before','after','observed'},
          'c04chrome':{'before','after','elapsedMs'}}

def validate_checks(scene, runs, checks):
    if scene.startswith('precise-'):
        rows=[r for r in checks if r.get('id')=='CP3.'+scene+'.summary']
        return [] if len(rows)==1 and rows[0].get('status') in ('PASS','FAIL') and isinstance(rows[0].get('numbers'),dict) else ['missing precise summary']
    errors=[]
    expected={f'CP3.{scene}.{v}.{i}' for v,n in VARIANTS[scene].items() for i in range(n)}
    if len(checks)!=len(expected): errors.append('CHECK total count mismatch')
    for ident in sorted(expected):
        rows=[r for r in checks if r.get('id')==ident]
        if len(rows)!=1: errors.append(ident+': CHECK count != 1'); continue
        row=rows[0]; numbers=row.get('numbers')
        if row.get('status') not in ('PASS','FAIL') or not isinstance(numbers,dict) or FIELDS[scene]-numbers.keys():
            errors.append(ident+': missing measurements')
    return errors
