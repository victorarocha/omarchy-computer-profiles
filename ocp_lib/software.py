"""Optional application selection and reproducible release resolution."""
import base64, glob, io, json, pathlib, re, tarfile, urllib.parse
from .core import execute, digest

OPTIONAL_APPS=('brumm','flatpak','google-chrome','bruno')
LABELS={'brumm':'brumm','flatpak':'Flatpak','google-chrome':'Google Chrome','bruno':'Bruno'}
HEX=re.compile(r'[0-9a-f]{64}')

def ask_apps():
    choices={}
    for app in OPTIONAL_APPS:
        while True:
            try: answer=input(f'Include {LABELS[app]}? [y/n]: ').strip().lower()
            except EOFError: raise ValueError(f'An inclusion answer is required for {LABELS[app]}') from None
            if answer in ('y','yes','n','no'):
                choices[app]=answer in ('y','yes');break
            print('Please answer yes or no.')
    return choices

def selected(app): return app.get('included',True)

def selection_metadata(app,choices):
    if app['id'] in choices:
        app['requested']=choices[app['id']]
        app['included']=choices[app['id']] or (app['id']=='flatpak' and choices['bruno'])
        if app['id']=='flatpak' and choices['bruno']:
            app['dependency_for']=['bruno']
    return app

def repositories(system,arch):
    """Read configured repository servers, including mirrorlists, without invoking pacman sync."""
    repos={};section=None;seen=set()
    def parse(path):
        nonlocal section
        if path in seen: return
        if not path.exists(): return
        seen.add(path)
        for line in path.read_text().splitlines():
            line=line.split('#',1)[0].strip()
            if not line: continue
            if line.startswith('[') and line.endswith(']'):
                section=line[1:-1]
                if section!='options': repos.setdefault(section,[])
            elif '=' in line:
                key,value=map(str.strip,line.split('=',1))
                if key=='Include':
                    for name in sorted(glob.glob(str(system/value.lstrip('/')))): parse(pathlib.Path(name))
                elif key=='Server' and section and section!='options':
                    server=value.replace('$repo',section).replace('$arch',arch).rstrip('/')
                    if server.startswith('https://') and '@' not in urllib.parse.urlsplit(server).netloc:
                        repos.setdefault(section,[]).append(server)
        seen.remove(path)
    parse(system/'etc/pacman.conf')
    return repos

def database_entries(blob):
    with tarfile.open(fileobj=io.BytesIO(blob),mode='r:*') as archive:
        for member in archive:
            if pathlib.PurePosixPath(member.name).name!='desc' or not member.isfile(): continue
            if member.size>1024*1024: raise ValueError('Oversized repository entry')
            fields={};key=None
            for line in archive.extractfile(member).read().decode().splitlines():
                if line.startswith('%') and line.endswith('%'): key=line.strip('%');fields[key]=[]
                elif line and key: fields[key].append(line)
            yield {k:v[0] for k,v in fields.items() if v}

def package_metadata(name,arch,system,fetch,latest=False):
    repos=repositories(system,arch)
    # Installed-version pinning can use the existing sync database; latest pinning always refreshes in memory.
    if not latest:
        for repo,servers in repos.items():
            db=system/f'var/lib/pacman/sync/{repo}.db'
            if db.exists() and servers:
                for entry in database_entries(db.read_bytes()):
                    if entry.get('NAME')==name and entry.get('ARCH') in [arch,'any']:
                        return entry,servers[0]
    errors=[]
    for repo,servers in repos.items():
        for server in servers:
            try:
                blob=fetch(f'{server}/{repo}.db')
                match=next((e for e in database_entries(blob) if e.get('NAME')==name and e.get('ARCH') in [arch,'any']),None)
                if match: return match,server
                break
            except (OSError,ValueError,tarfile.TarError) as error: errors.append(str(error))
    raise ValueError(f'No compatible {name} package in configured HTTPS repositories'+(f': {errors[-1]}' if errors else ''))

def package_pin(app,arch,system,fetch):
    name=app['package'];version=app.get('captured_version')
    entry,server=package_metadata(name,arch,system,fetch,latest=not bool(version))
    if version and entry.get('VERSION')!=version:
        # Archives/caches retain older installed releases; never quietly substitute latest.
        cache=system/'var/cache/pacman/pkg'
        candidates=[]
        for path in cache.glob(f'{name}-*.pkg.tar.*'):
            if path.name.endswith('.sig'): continue
            if execute(['pacman','-Qp',path],optional=True).strip()==f'{name} {version}': candidates.append(path)
        if candidates:
            path=candidates[0];filename=path.name;checksum=digest(path.read_bytes())
            sigpath=path.with_name(path.name+'.sig')
            signature=sigpath.read_bytes() if sigpath.exists() else fetch(server+'/'+urllib.parse.quote(filename)+'.sig')
            url=server+'/'+urllib.parse.quote(filename)
        elif name=='flatpak' and arch=='x86_64':
            filename=f"flatpak-{version.split(':',1)[-1]}-{arch}.pkg.tar.zst"
            url='https://archive.archlinux.org/packages/f/flatpak/'+urllib.parse.quote(filename)
            checksum=digest(fetch(url));signature=fetch(url+'.sig')
        else:
            raise ValueError(f'Cannot pin installed {name} {version}: its exact signed package is absent from repositories/cache. Retain or host that package before capture.')
    else:
        version=version or entry['VERSION'];filename=entry['FILENAME'];checksum=entry.get('SHA256SUM','')
        if not HEX.fullmatch(checksum): raise ValueError(f'Missing package SHA-256 for {name}')
        if pathlib.PurePosixPath(filename).name!=filename: raise ValueError('Unsafe package filename')
        url=server+'/'+urllib.parse.quote(filename)
        if entry.get('PGPSIG'):
            signature=base64.b64decode(entry['PGPSIG'],validate=True)
        else:
            cached_signature=system/'var/cache/pacman/pkg'/(filename+'.sig')
            signature=cached_signature.read_bytes() if cached_signature.exists() else fetch(url+'.sig')
    if not signature or len(signature)>32768: raise ValueError(f'Invalid package signature for {name}')
    return {'version':version,'architecture':arch,'url':url,'sha256':checksum,
            'signature':base64.b64encode(signature).decode(),'source':'installed' if app.get('captured_version') else 'latest'}

def installed_bruno(arch):
    # Prefer the current user's installation, then the system installation.
    for scope in ['--user','--system']:
        commit=execute(['flatpak','info',scope,'--arch='+arch,'--show-commit','com.usebruno.Bruno//stable'],optional=True).strip()
        if HEX.fullmatch(commit):
            origin=execute(['flatpak','info',scope,'--show-origin','com.usebruno.Bruno//stable'],optional=True).strip()
            if origin!='flathub': raise ValueError('Installed Bruno is not from Flathub; its release cannot be pinned with the Flathub recipe')
            return {'commit':commit,'architecture':arch,'source':'installed'}
    return None

def bruno_pin(arch,fetch):
    installed=installed_bruno(arch)
    if installed: return installed
    for name in ['bruno','bruno-bin']:
        package=execute(['pacman','-Q',name],optional=True).strip()
        if not package: continue
        match=re.fullmatch(r'(?:[0-9]+:)?([0-9]+\.[0-9]+\.[0-9]+)-[0-9]+',package.split(' ',1)[1])
        if not match: raise ValueError('Cannot determine installed native Bruno release version')
        version=match.group(1);tag='v'+version
        asset=f"bruno_{version}_{'arm64' if arch=='aarch64' else arch}_linux.AppImage"
        release=json.loads(fetch('https://api.github.com/repos/usebruno/bruno/releases/tags/'+tag))
        matches=[a for a in release.get('assets',[]) if a['name']==asset]
        if not matches: raise ValueError(f'No compatible Bruno {tag} AppImage for {arch}')
        entry=matches[0];url=f'https://github.com/usebruno/bruno/releases/download/{tag}/{asset}'
        checksum=entry.get('digest','').removeprefix('sha256:')
        if entry.get('browser_download_url')!=url or not HEX.fullmatch(checksum): raise ValueError('Invalid Bruno AppImage release metadata')
        return {'version':version,'tag':tag,'url':url,'sha256':checksum,'architecture':arch,'source':'installed','kind':'appimage'}
    ref=f'app/com.usebruno.Bruno/{arch}/stable'
    commit=fetch('https://dl.flathub.org/repo/refs/heads/'+ref).decode().strip()
    if not HEX.fullmatch(commit): raise ValueError(f'No compatible stable Bruno release for {arch}')
    return {'commit':commit,'architecture':arch,'source':'latest'}

def brumm_pin(app,arch,fetch):
    suffix={'x86_64':'amd64','aarch64':'arm64'}.get(arch)
    if not suffix: raise ValueError(f'No supported brumm release architecture: {arch}')
    tag=app.get('tag');base='https://api.github.com/repos/chriopter/brumm/releases'
    if tag:
        releases=[json.loads(fetch(base+'/tags/'+tag))]
    else:
        releases=json.loads(fetch(base+'?per_page=100'))
        if not isinstance(releases,list): raise ValueError('Invalid brumm release list')
    name=f'brumm-linux-{suffix}.tar.gz'
    for release in releases:
        if release.get('draft') or release.get('prerelease'): continue
        matches=[a for a in release.get('assets',[]) if a['name']==name]
        if not matches: continue
        release_tag=release.get('tag_name') or tag
        if not release_tag or not re.fullmatch(r'v\d+\.\d+\.\d+',release_tag): continue
        asset=matches[0];url=f'https://github.com/chriopter/brumm/releases/download/{release_tag}/{name}'
        if asset.get('browser_download_url')!=url: raise ValueError('Unexpected brumm release URL')
        checksum=asset.get('digest','').removeprefix('sha256:')
        if not HEX.fullmatch(checksum): raise ValueError('Missing brumm release SHA-256')
        if digest(fetch(url))!=checksum: raise ValueError('Release asset checksum mismatch')
        return {'version':release_tag,'architecture':arch,'tag':release_tag,'asset':name,'sha256':checksum,'source':'installed' if tag else 'latest'}
    raise ValueError(f'No compatible brumm {tag or "stable"} release for {arch}')

def resolve_apps(manifest,fetch,system=pathlib.Path('/')):
    arch=manifest['hardware']['architecture']
    bruno=next((a for a in manifest['software'] if a['id']=='bruno' and selected(a)),None)
    if bruno:
        bruno['pin']=bruno.get('pin') or bruno_pin(arch,fetch)
        flatpak=next(a for a in manifest['software'] if a['id']=='flatpak')
        if bruno['pin'].get('kind')=='appimage':
            bruno.update(provider='github-appimage',repository='usebruno/bruno')
            if not flatpak.get('requested',True):
                flatpak['included']=False;flatpak.pop('dependency_for',None)
        elif not flatpak.get('requested',True):
            flatpak.update(included=True,dependency_for=['bruno'])
            print('Bruno requires Flatpak; Flatpak will be included as a runtime dependency.')
    for app in manifest['software']:
        if not selected(app) or app['id'] not in OPTIONAL_APPS: continue
        if app.get('pin') and app['id']!='bruno': continue
        print(f"Pinning {LABELS[app['id']]} ({'installed' if app.get('captured_version') or app.get('tag') else 'installed if available, otherwise latest compatible'})…",flush=True)
        if app['id']=='brumm':
            pin=brumm_pin(app,arch,fetch);app.update(tag=pin['tag'],asset=pin['asset'],sha256=pin['sha256'])
        elif app['id']=='bruno': pin=app['pin']
        else: pin=package_pin(app,arch,system,fetch)
        app['pin']=pin
    manifest['warnings']=[w for w in manifest['warnings'] if not w.startswith('brumm release digest')]
    return manifest

def validate_pin(app,arch):
    pin=app.get('pin')
    if pin is None: return # Legacy profiles remain readable; new optional selections require pins when applied.
    if not isinstance(pin,dict) or pin.get('architecture')!=arch or pin.get('source') not in ['installed','latest']:
        raise ValueError('Invalid software pin metadata')
    if app['id']=='bruno' and pin.get('kind')=='appimage':
        if app.get('provider')!='github-appimage': raise ValueError('Bruno pin/provider mismatch')
        version=pin.get('version','');asset=f"bruno_{version}_{'arm64' if arch=='aarch64' else arch}_linux.AppImage"
        expected=f'https://github.com/usebruno/bruno/releases/download/v{version}/{asset}'
        if not re.fullmatch(r'\d+\.\d+\.\d+',version) or pin.get('url')!=expected or not HEX.fullmatch(pin.get('sha256','')):
            raise ValueError('Invalid Bruno AppImage pin')
    elif app['id']=='bruno':
        if not HEX.fullmatch(pin.get('commit','')): raise ValueError('Invalid Bruno commit pin')
    elif app['id']=='brumm':
        if pin.get('version')!=app.get('tag') or pin.get('tag')!=app.get('tag') or pin.get('asset')!=app.get('asset') or pin.get('sha256')!=app.get('sha256'):
            raise ValueError('Brumm pin does not match its release')
    else:
        version=pin.get('version','');url=pin.get('url','')
        parts=urllib.parse.urlsplit(url)
        if not re.fullmatch(r'[A-Za-z0-9.+_:~\-]+',version): raise ValueError('Invalid package version pin')
        filename=urllib.parse.unquote(parts.path.rsplit('/',1)[-1])
        # Epoch may be omitted in Arch filenames, but package version verification remains exact at install time.
        if pathlib.PurePosixPath(filename).name!=filename or '\\' in filename: raise ValueError('Unsafe package filename')
        versions={version,version.split(':',1)[-1]}
        if not any(filename.startswith(f"{app['package']}-{v}-") for v in versions) or not filename.endswith(('.pkg.tar.zst','.pkg.tar.xz')):
            raise ValueError('Pinned artifact is not the requested package version')
        if parts.scheme!='https' or not parts.netloc or parts.username or parts.password: raise ValueError('Unsafe package URL')
        if not HEX.fullmatch(pin.get('sha256','')): raise ValueError('Invalid package digest pin')
        try: signature=base64.b64decode(pin.get('signature',''),validate=True)
        except ValueError: raise ValueError('Invalid package signature encoding') from None
        if not signature or len(signature)>32768: raise ValueError('Missing package signature')
