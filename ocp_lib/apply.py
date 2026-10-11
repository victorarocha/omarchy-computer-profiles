import datetime, json, os, pathlib, shlex, shutil, subprocess, tarfile, tempfile, urllib.request
from .core import (ROOT, APP_PACKAGES, SERVICES, validate, hardware, limine_state, render_limine,
                   digest, safe_id, execute, read, relpath)

SECTIONS={'hardware','boot','software','plugins','preferences'}

def command(args):
    print('$',shlex.join(map(str,args)),flush=True)
    subprocess.run([str(x) for x in args],check=True)

def download(url):
    request=urllib.request.Request(url,headers={'User-Agent':'omarchy-computer-profiles/0.1'})
    with urllib.request.urlopen(request,timeout=60) as response:
        data=response.read(512*1024*1024+1)
        if len(data)>512*1024*1024: raise ValueError('Release download exceeds 512 MiB')
        return data

def lock(folder):
    m=validate(folder)
    from .software import resolve_apps
    m=resolve_apps(m,download)
    (folder/'profile.json').write_text(json.dumps(m,indent=2)+'\n');validate(folder)
    print('Locked and verified release assets for',m['id'])

def ensure_no_links(path):
    for parent in [path,*path.parents]:
        if parent.is_symlink(): raise ValueError(f'Refusing symlink destination: {parent}')

def match_hardware(m,target,allow_variant=False):
    for key in ['vendor','model','architecture']:
        if m['hardware'][key]!=target[key] or target[key]=='unknown': raise ValueError(f'Hardware mismatch for {key}: expected {m["hardware"][key]}, got {target[key]}')
    def relevant(hw):
        return {(p['vendor'],p['device']) for p in hw['pci'] if p['class'].startswith(('0x03','0x02'))}
    if relevant(m['hardware'])!=relevant(target) and not allow_variant:
        raise ValueError('GPU/network PCI IDs differ; inspect the profile and use --allow-hardware-variant if appropriate')

class Transaction:
    def __init__(self,home,profile):
        stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        self.folder=home/'.local/state/ocp/backups'/f'{stamp}-{profile}'
        ensure_no_links(self.folder)
        self.folder.mkdir(parents=True,mode=0o700)
        self.entries=[];self.flush()
        print('Recovery journal:',self.folder,flush=True)
    def flush(self):
        (self.folder/'journal.json').write_text(json.dumps({'version':1,'home':str(pathlib.Path.home()),'entries':self.entries},indent=2)+'\n')
    def put(self,target,data,mode,privileged=False):
        ensure_no_links(target)
        if target.exists() and not target.is_file(): raise ValueError(f'Expected regular file: {target}')
        if target.exists() and target.read_bytes()==data and target.stat().st_mode&0o777==mode: return
        entry={'target':str(target),'privileged':privileged,'backup':None,'mode':mode}
        if target.exists():
            backup=f'files/{len(self.entries)}';source=self.folder/backup;source.parent.mkdir(exist_ok=True)
            shutil.copy2(target,source);entry['backup']=backup;entry['mode']=target.stat().st_mode&0o777
        self.entries.append(entry);self.flush()
        if privileged:
            with tempfile.NamedTemporaryFile() as tmp:
                tmp.write(data);tmp.flush();command(['sudo','install','-D','-m',f'{mode:o}',tmp.name,target])
        else:
            target.parent.mkdir(parents=True,exist_ok=True)
            fd,name=tempfile.mkstemp(prefix='.ocp-',dir=target.parent)
            try:
                with os.fdopen(fd,'wb') as stream: stream.write(data)
                os.chmod(name,mode);os.replace(name,target)
            finally:
                if os.path.exists(name): os.unlink(name)
    def enable(self,service):
        prior=subprocess.run(['systemctl','is-enabled',service],capture_output=True,text=True,check=False).stdout.strip()
        if prior=='enabled': return
        if prior=='masked': raise ValueError(f'{service} is masked; resolve this before applying')
        self.entries.append({'service':service,'previous':prior});self.flush()
        command(['sudo','systemctl','enable',service])

def restore(folder,execute_changes=False):
    folder=folder.resolve();home=pathlib.Path.home();ensure_no_links(folder)
    if not folder.is_relative_to(home/'.local/state/ocp/backups'): raise ValueError('Journal must be under this user’s OCP backups directory')
    journal=json.loads((folder/'journal.json').read_text())
    if journal.get('home')!=str(home): raise ValueError('Journal belongs to another user')
    from .core import allowed_file
    for entry in reversed(journal['entries']):
        if 'service' in entry:
            if entry['service'] not in SERVICES: raise ValueError('Invalid journal service')
            print('Disable service enabled by OCP:',entry['service'])
            if execute_changes: command(['sudo','systemctl','disable',entry['service']])
            continue
        target=pathlib.Path(entry['target']);ensure_no_links(target)
        relative=str(target.relative_to(home)) if target.is_relative_to(home) else str(target).lstrip('/')
        scope='home' if target.is_relative_to(home) else 'system'
        if not allowed_file(scope,relative) and relative not in ['etc/default/limine','.local/bin/brumm','.local/bin/brumm-gui','.local/share/applications/brumm.desktop','.config/systemd/user/brumm.service','.local/share/brumm/LICENSE','.local/bin/bruno','.local/share/applications/ocp-bruno.desktop']:
            raise ValueError('Invalid restore target')
        print('Restore',target)
        if not execute_changes: continue
        if entry['backup']:
            source=folder/str(relpath(entry['backup']));ensure_no_links(source)
            if entry['privileged']: command(['sudo','install','-D','-m',f"{entry['mode']:o}",source,target])
            else: shutil.copy2(source,target)
        elif target.exists():
            if entry['privileged']: command(['sudo','rm','--',target])
            else: target.unlink()
    if execute_changes: print('File restore complete. If hardware/boot changed, run sudo mkinitcpio -P and sudo limine-update before rebooting. Packages and app setup are not rolled back.')

def install_brumm(app,tx,home):
    url=f"https://github.com/chriopter/brumm/releases/download/{app['tag']}/{app['asset']}"
    blob=download(url)
    if digest(blob)!=app['sha256']: raise ValueError('brumm release checksum mismatch')
    import io
    with tarfile.open(fileobj=io.BytesIO(blob),mode='r:gz') as archive:
        mapping={'brumm/brumm':('.local/bin/brumm',0o755),'brumm/brumm-gui':('.local/bin/brumm-gui',0o755),
                 'brumm/omarchy/brumm.desktop':('.local/share/applications/brumm.desktop',0o644),
                 'brumm/omarchy/brumm.service':('.config/systemd/user/brumm.service',0o644),
                 'brumm/LICENSE':('.local/share/brumm/LICENSE',0o644)}
        members={x.name:x for x in archive.getmembers()}
        for name,(dest,mode) in mapping.items():
            member=members.get(name)
            if member is None or not member.isfile() or member.size>120*1024*1024: raise ValueError('Unsupported brumm archive layout')
            data=archive.extractfile(member).read()
            tx.put(home/dest,data,mode)
    command(['systemctl','--user','daemon-reload'])

def install_pinned_packages(apps,yes=False):
    import base64, urllib.parse
    if not apps: return
    with tempfile.TemporaryDirectory(prefix='ocp-packages-') as tmp:
        paths=[]
        for app in apps:
            pin=app['pin'];blob=download(pin['url'])
            if digest(blob)!=pin['sha256']: raise ValueError(f"{app['id']} package checksum mismatch")
            filename=urllib.parse.unquote(urllib.parse.urlsplit(pin['url']).path.rsplit('/',1)[-1])
            if pathlib.PurePosixPath(filename).name!=filename or '\\' in filename: raise ValueError('Unsafe package filename')
            path=pathlib.Path(tmp)/filename;path.write_bytes(blob)
            path.with_name(filename+'.sig').write_bytes(base64.b64decode(pin['signature'],validate=True))
            identity=execute(['pacman','-Qp',path]).strip()
            if identity!=f"{app['package']} {pin['version']}": raise ValueError('Pinned package identity/version mismatch')
            # Check trusted signatures before any package installation or upgrade.
            command(['pacman-key','--verify',str(path)+'.sig',path])
            paths.append(path)
        command(['sudo','pacman','-U',*(['--noconfirm'] if yes else []),*paths])
        for app in apps:
            if execute(['pacman','-Q',app['package']]).strip()!=f"{app['package']} {app['pin']['version']}":
                raise ValueError(f"{app['id']} installed package does not match its pin")

def install_bruno(app,yes=False,tx=None,home=None):
    if app.get('provider')=='github-appimage':
        pin=app['pin'];blob=download(pin['url'])
        if digest(blob)!=pin['sha256']: raise ValueError('Bruno AppImage checksum mismatch')
        tx.put(home/'.local/bin/bruno',blob,0o755)
        desktop='[Desktop Entry]\nType=Application\nName=Bruno\nExec=bruno\nTerminal=false\nCategories=Development;\n'
        tx.put(home/'.local/share/applications/ocp-bruno.desktop',desktop.encode(),0o644)
        return
    command(['flatpak','remote-add','--user','--if-not-exists','flathub','https://dl.flathub.org/repo/flathub.flatpakrepo'])
    ref=f"com.usebruno.Bruno/{app.get('pin',{}).get('architecture','x86_64')}/stable"
    command(['flatpak','install','--user',*(['-y'] if yes else []),'flathub',ref])
    if app.get('pin'):
        commit=app['pin']['commit']
        command(['flatpak','update','--user',*(['-y'] if yes else []),'--commit='+commit,ref])
        installed=execute(['flatpak','info','--user','--show-commit',ref]).strip()
        if installed!=commit: raise ValueError('Bruno deployed commit does not match its pin')


def apply(folder, sections, execute_changes=False, yes=False, allow_variant=False):
    m=validate(folder);home=pathlib.Path.home();system=pathlib.Path('/')
    if not sections or sections-SECTIONS: raise ValueError('Invalid sections')
    print('Profile:',m['id'],' | sections:',', '.join(sorted(sections)))
    print('Mode:','APPLY' if execute_changes else 'PREVIEW — no changes')
    for warning in m['warnings']: print('NOTE:',warning)
    if execute_changes:
        if os.geteuid()==0: raise ValueError('Run as the desktop user; OCP uses sudo only for system operations')
        if not shutil.which('omarchy'): raise ValueError('Install Omarchy before applying an OCP profile')
        match_hardware(m,hardware(),allow_variant)
    writes=[];boot_data=None
    for f in m['files']:
        part='hardware' if f['scope']=='system' else ('plugins' if f['path'].startswith('.config/omarchy/plugins/') else 'preferences')
        if part not in sections: continue
        target=(home if f['scope']=='home' else system)/f['path']
        print('Write',target)
        if execute_changes: ensure_no_links(target)
        writes.append((f,target))
    from .software import selected, OPTIONAL_APPS
    apps=[a for a in m['software'] if selected(a)]
    if 'software' in sections:
        print('Install:',', '.join(a['id'] for a in apps))
        for app in apps:
            if app.get('pin'): print('  Pin:',app['id'],app['pin'].get('version') or app['pin'].get('commit'))
            if 'included' in app and app['id'] in OPTIONAL_APPS and not app.get('pin'):
                if execute_changes: raise ValueError(f"{app['id']} is not pinned; run ocp lock PROFILE first")
                print('UNRESOLVED:',app['id'])
            if app['id']=='brumm' and (not app.get('sha256') or not app.get('tag') or not app.get('asset')):
                if execute_changes: raise ValueError('brumm is not locked: run ocp lock PROFILE first')
                print('UNRESOLVED: run ocp lock to verify brumm release')
    if 'hardware' in sections: print('Install hardware packages:',', '.join(x['name'] for x in m['hardware_packages']))
    if 'boot' in sections:
        states,_=limine_state(system)
        boot_data=render_limine(read(system/'etc/default/limine'),states,m['boot']['hardware_options'])
        print('Merge portable kernel options into /etc/default/limine; preserve target root/encryption settings')
        print(json.dumps(m['boot']['hardware_options'],indent=2))
        if execute_changes: ensure_no_links(system/'etc/default/limine')
    if not execute_changes: return
    required=['sudo']
    if sections & {'hardware','software'}: required += ['pacman','yay']
    if 'hardware' in sections: required += ['mkinitcpio','systemctl']
    if 'software' in sections and any(a.get('pin') and a['id'] in ['flatpak','google-chrome'] for a in apps): required += ['pacman-key']
    if 'software' in sections and any(a['id']=='brumm' for a in apps): required += ['systemctl']
    if 'boot' in sections: required += ['limine-update']
    for cmd in required:
        if not shutil.which(cmd): raise ValueError(f'Required command missing: {cmd}')
    # All static validation and destination checks happen before package/file mutations.
    tx=Transaction(home,m['id'])
    try:
        arch=[];aur=[]
        if 'hardware' in sections:
            for pkg in m['hardware_packages']: (aur if pkg['provider']=='aur' else arch).append(pkg['name'])
        if 'software' in sections:
            for app in apps:
                if app['id'] in ['brumm','bruno']: continue
                if app.get('pin'): continue # Exact package artifacts are installed below.
                if execute(['pacman','-Si',app['package']],optional=True): arch.append(app['package'])
                else: aur.append(app['package'])
            if any(a['id']=='brumm' for a in apps): arch.append('qt6-multimedia')
            if any(a.get('provider')=='github-appimage' for a in apps): arch.append('fuse2')
        if arch: command(['sudo','pacman','-Syu','--needed',*(['--noconfirm'] if yes else []),*sorted(set(arch))])
        if aur: command(['yay','-S','--needed',*(['--noconfirm'] if yes else []),*sorted(set(aur))])
        if 'software' in sections:
            install_pinned_packages([a for a in apps if a['id'] in ['flatpak','google-chrome'] and a.get('pin')],yes)
            bruno=next((a for a in apps if a['id']=='bruno'),None)
            if bruno: install_bruno(bruno,yes,tx,home)
            brumm=next((a for a in apps if a['id']=='brumm'),None)
            if brumm: install_brumm(brumm,tx,home)
        for f,target in writes:
            data=(folder/'files'/f['scope']/f['path']).read_bytes()
            from .core import ASSET_SUFFIXES
            if pathlib.Path(f['path']).suffix.lower() not in ASSET_SUFFIXES and not data.startswith(b'\x7fELF'):
                data=data.decode().replace('__HOME__',str(home)).encode()
            tx.put(target,data,f['mode'],f['scope']=='system')
        if boot_data is not None: tx.put(system/'etc/default/limine',boot_data.encode(),0o644,True)
        if 'hardware' in sections:
            command(['sudo','mkinitcpio','-P'])
            for service in m['services']: tx.enable(service)
        if 'boot' in sections: command(['sudo','limine-update'])
    except Exception:
        print('Apply stopped. Restore files with: ./ocp restore',tx.folder,'--execute',flush=True)
        raise
    print('Applied. Backup:',tx.folder)
    print('Log out/in for shell preferences. Reboot after hardware/boot changes. Sign in to apps separately.')
    print('Plugin sources are installed; review upstream runtime setup instructions before expecting native helpers to work.')
