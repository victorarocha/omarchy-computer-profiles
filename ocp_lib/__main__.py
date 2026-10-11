import argparse, json, pathlib, subprocess, sys
from .core import ROOT, VERSION, capture, validate, load_manifest, safe_id, hardware
from .apply import apply, restore, lock, SECTIONS

def main():
    parser=argparse.ArgumentParser(prog='ocp',description='OCP — share working Omarchy configurations by computer model')
    parser.add_argument('--version',action='version',version=VERSION)
    sub=parser.add_subparsers(dest='command',required=True)
    create=sub.add_parser('capture',help='Capture this computer and verify/pin release downloads in one step')
    create.add_argument('--id');create.add_argument('--description',default='')
    sub.add_parser('list',help='List repository profiles')
    sub.add_parser('detect',help='Print hardware identifiers (no serial numbers)')
    for name in ['show','validate','lock','apply','share']:
        item=sub.add_parser(name,help={'show':'Print a profile','validate':'Validate schema, paths and checksums','lock':'Resolve and verify selected application versions','apply':'Preview/apply an existing profile','share':'Stage/commit a profile; optionally push to your configured remote'}[name])
        item.add_argument('profile')
        if name=='apply':
            item.add_argument('--sections',default=','.join(sorted(SECTIONS)),help='Comma-separated hardware,boot,software,plugins,preferences')
            item.add_argument('--execute',action='store_true');item.add_argument('--yes',action='store_true',help='Noninteractive package confirmations')
            item.add_argument('--allow-hardware-variant',action='store_true',help='Allow differing GPU/network PCI IDs within the same model')
        if name=='share':
            item.add_argument('--commit',action='store_true');item.add_argument('--push',action='store_true');item.add_argument('--message')
    item=sub.add_parser('restore',help='Preview/restore a local OCP file backup')
    item.add_argument('backup',type=pathlib.Path);item.add_argument('--execute',action='store_true')
    args=parser.parse_args()
    if args.command=='capture': print('Created',capture(args.id,note=args.description));return
    if args.command=='detect': print(json.dumps(hardware(),indent=2));return
    if args.command=='restore': restore(args.backup,args.execute);return
    if args.command=='list':
        rows=[('PROFILE','COMPUTER','STATUS','AUTHOR')]
        for path in sorted((ROOT/'profiles').glob('*/profile.json')):
            m=load_manifest(path.parent)
            rows.append((m['id'],f"{m['hardware']['vendor']} {m['hardware']['model']}",m['validation']['status'],m.get('author','Unknown')))
        widths=[max(len(row[column]) for row in rows) for column in range(3)]
        for row in rows:
            print('  '.join(value.ljust(width) for value,width in zip(row,widths))+'  '+row[3])
        return
    folder=ROOT/'profiles'/safe_id(args.profile)
    m=validate(folder)
    if args.command=='show': print(json.dumps(m,indent=2))
    elif args.command=='validate': print('Valid:',m['id'],f"({len(m['files'])} files, {len(m['plugins'])} plugins)")
    elif args.command=='lock': lock(folder)
    elif args.command=='apply': apply(folder,set(args.sections.split(',')),args.execute,args.yes,args.allow_hardware_variant)
    elif args.command=='share':
        if args.push and not args.commit: raise ValueError('--push requires --commit')
        subprocess.run(['git','-C',str(ROOT),'add','--',f'profiles/{m["id"]}'],check=True)
        if args.commit: subprocess.run(['git','-C',str(ROOT),'commit','-m',args.message or f'Add/update {m["id"]} profile','--',f'profiles/{m["id"]}'],check=True)
        if args.push: subprocess.run(['git','-C',str(ROOT),'push'],check=True)
        print('Profile staged'+(' and committed' if args.commit else '')+(' and pushed' if args.push else ''))

if __name__=='__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print('OCP:',error,file=sys.stderr);sys.exit(1)
