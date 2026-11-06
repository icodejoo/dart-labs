"""CP3 aliases preserve source batch argv/counts; no device I/O on import."""
def resolve(manifest, names):
    aliases = manifest.get('aliases', {})
    output = []
    def visit(name, stack):
        if name in stack:
            raise ValueError('alias cycle: ' + name)
        if name in aliases:
            for child in aliases[name]['batches']:
                visit(child, stack + [name])
        elif name not in output:
            output.append(name)
    for name in names:
        visit(name, [])
    return output
