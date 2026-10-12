from __future__ import annotations
import datetime, hashlib, json, os, pathlib, platform, re, shlex, shutil, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = '0.1.0'
HOME_FILES = {'.config/hypr/input.lua', '.config/hypr/monitors.lua',
              '.config/omarchy/shell.json', '.config/omarchy/shell.toml',
              '.config/omarchy/magic-trackpad.json', '.config/zapfast/settings.json',
              '.config/brumm/options.json'}
SYSTEM_DIRS = ('etc/modprobe.d', 'etc/modules-load.d', 'etc/udev/rules.d',
               'etc/X11/xorg.conf.d', 'etc/mkinitcpio.conf.d')
SYSTEM_FILES = {'etc/mbpfan.conf', 'etc/thermald/thermal-conf.xml'}
HARDWARE_PACKAGES = {'broadcom-wl','broadcom-wl-dkms','dkms','intel-ucode','amd-ucode',
                    'vulkan-radeon','vulkan-intel','nvidia','nvidia-open','nvidia-dkms',
                    'nvidia-open-dkms','nvidia-utils','mesa','mbpfan','thermald',
                    'linux-firmware','sof-firmware','linux-headers','linux-omarchy-headers'}
APP_PACKAGES = {'zapfast':'zapfast-bin','flatpak':'flatpak','google-chrome':'google-chrome','obsidian':'obsidian'}
SERVICES = {'mbpfan.service','thermald.service'}
# Only these families are portable by default; unknown parameters require explicit review.
PORTABLE_PREFIXES = ('amdgpu.','radeon.','i915.','xe.','nouveau.','nvidia.','nvidia_drm.',
                     'snd_hda_intel.','snd-intel-dspcfg.','usbcore.','usbhid.','hid_apple.',
                     'applesmc.','pcie_aspm','pci=','intel_iommu','amd_iommu','iommu=',
                     'acpi_osi','acpi_backlight','acpi_enforce_resources','processor.max_cstate',
                     'intel_idle.max_cstate','nvme_core.','ahci.','libata.','video=',
                     'module_blacklist=','modprobe.blacklist=','rfkill.','bluetooth.',
                     'acpi=','acpi.','iomem=','clocksource=','tsc=','noapic','nolapic',
                     'nohz=','nomodeset','efi=','mem_sleep_default=','reboot=','idle=','drm.')
ASSET_SUFFIXES = {'.png','.jpg','.jpeg','.webp','.gif','.ico','.icns','.woff','.woff2','.ttf','.qsb','.so'}
SECRET = re.compile(r'-----BEGIN .*PRIVATE KEY|\bAKIA[A-Z0-9]{16}\b|\bgh[pousr]_[A-Za-z0-9]{20,}|\bsk-[A-Za-z0-9]{20,}')
SENSITIVE_KEY = re.compile(r'token|password|secret|api.?key|oauth|account|email|chat|location|latitude|longitude|proxy',re.I)

def execute(args, *, optional=False):
    try:
        p = subprocess.run([str(x) for x in args], capture_output=True, text=True, check=False)
    except FileNotFoundError:
        if optional: return ''
        raise ValueError(f'Missing command: {args[0]}')
    if p.returncode and not optional: raise ValueError(f'{shlex.join(map(str,args))}: {p.stderr.strip()}')
    return p.stdout if p.returncode == 0 else ''

def read(path):
    try: return pathlib.Path(path).read_text().strip()
    except (FileNotFoundError, PermissionError): return ''

def slug(text):
    return re.sub(r'[^a-z0-9]+','-',text.lower()).strip('-') or 'unknown'

def safe_id(value):
    if not re.fullmatch(r'[a-z0-9][a-z0-9._-]{0,119}',value): raise ValueError('Invalid profile ID')
    return value

def relpath(value):
    p=pathlib.PurePosixPath(value)
    if not value or p.is_absolute() or '..' in p.parts or '\\' in value: raise ValueError(f'Unsafe path: {value}')
    return p

def digest(data): return hashlib.sha256(data).hexdigest()

def clean_json(value):
    if isinstance(value,dict): return {k:clean_json(v) for k,v in value.items() if not SENSITIVE_KEY.search(k)}
    if isinstance(value,list): return [clean_json(v) for v in value]
    return value

def hardware(system=pathlib.Path('/')):
    dmi=system/'sys/class/dmi/id'
    info={key:read(dmi/name) or 'unknown' for key,name in [('vendor','sys_vendor'),('model','product_name'),('board','board_name')]}
    info['architecture']=platform.machine()
    info['pci']=sorted([{'vendor':read(p/'vendor'),'device':read(p/'device'),'class':read(p/'class'),
                         'subsystem_vendor':read(p/'subsystem_vendor'),'subsystem_device':read(p/'subsystem_device'),
                         'driver':(p/'driver').resolve().name if (p/'driver').exists() else None}
                        for p in (system/'sys/bus/pci/devices').glob('*')],key=lambda x:json.dumps(x,sort_keys=True))
    cpu=read(system/'proc/cpuinfo')
    match=re.search(r'^model name\s*:\s*(.+)$',cpu,re.M)
    info['cpu']=match.group(1) if match else platform.processor()
    return info

ASSIGN = re.compile(r'^\s*KERNEL_CMDLINE\[([A-Za-z0-9_.+*-]+)\]\s*(\+?=)\s*(.*?)\s*$')

def parse_limine(text, initial=None):
    """Parse literal assignments without executing/sourcing shell configuration."""
    result={k:list(v) for k,v in (initial or {}).items()}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'): continue
        if 'KERNEL_CMDLINE[' not in line: continue
        m=ASSIGN.fullmatch(line)
        if not m: raise ValueError('Unsupported Limine cmdline syntax; use one literal assignment per line')
        key,op,value=m.groups()
        if '$' in value or '`' in value or '\\' in value.replace('\\"',''): raise ValueError('Dynamic Limine options cannot be safely captured')
        if value[:1] in ['"',"'"]:
            if value[-1:] != value[:1]: raise ValueError('Unbalanced Limine assignment')
            value=value[1:-1]
        value=value.replace('\\"','"')
        tokens=shlex.split(value,comments=False)
        result[key]=(result.get(key,[]) if op=='+=' else [])+tokens
    return result

def limine_state(system):
    states={}; sources=[]
    paths=sorted((system/'usr/share/limine-entry-tool.d').glob('*.conf'))
    paths += [system/'etc/limine-entry-tool.conf']
    paths += sorted((system/'etc/limine-entry-tool.d').glob('*.conf'))
    paths += [system/'etc/default/limine']
    for p in paths:
        if p.exists():
            text=p.read_text(); states=parse_limine(text,states)
            if 'KERNEL_CMDLINE[' in text: sources.append('/'+str(p.relative_to(system)))
    if not states:
        text=read(system/'etc/kernel/cmdline') or read(system/'proc/cmdline')
        states={'default':shlex.split(text)}
        sources.append('/etc/kernel/cmdline or /proc/cmdline')
    return states,sources

def classify_options(options):
    portable=[]; omitted=[]; review=[]
    for opt in options:
        key=opt.split('=',1)[0]
        if key in ['root','rootflags','rootfstype','cryptdevice','cryptkey','resume','resume_offset','initrd','BOOT_IMAGE','rd.luks.name','rd.luks.uuid','rd.luks.options'] or re.search(r'UUID|PARTUUID|/dev/|/home/|https?://',opt,re.I):
            omitted.append(key) # Never retain original disk identifiers, even in reports.
        elif opt.startswith(PORTABLE_PREFIXES): portable.append(opt)
        else: review.append(opt if key in {'rw','ro','quiet','splash','loglevel','zswap.enabled','mitigations','nowatchdog'} else key)
    return portable,sorted(set(omitted)),review

def merge_options(target, additions):
    keys={x.split('=',1)[0] for x in additions}
    return [x for x in target if x.split('=',1)[0] not in keys]+list(dict.fromkeys(additions))

def render_limine(existing, states, profile_options):
    # OCP only emits hardware options; root/encryption come from TARGET state.
    start='# BEGIN OCP KERNEL OPTIONS';end='# END OCP KERNEL OPTIONS'
    existing=re.sub(re.escape(start)+r'.*?'+re.escape(end)+r'\n?','',existing,flags=re.S)
    lines=[start]
    for scope,options in sorted(profile_options.items()):
        if not options: continue
        base=states.get(scope,states.get('default',[]))
        if not any(x.startswith('root=') for x in base): raise ValueError('Target kernel options have no root=; refusing boot changes')
        merged=merge_options(base,options)
        if any(any(c in x for c in ['"',"'",'$','`','\n','\r','\\']) for x in merged): raise ValueError('Target kernel options require unsupported quoting')
        def quote_option(x):
            if ' ' not in x: return x
            key,sep,value=x.partition('=')
            if not sep: raise ValueError('Invalid spaced kernel argument')
            return key+'="'+value+'"'
        value=' '.join(quote_option(x) for x in merged)
        value=value.replace('"','\\"')
        lines.append(f'KERNEL_CMDLINE[{scope}]="{value}"')
    lines.append(end)
    return existing.rstrip()+'\n\n'+'\n'.join(lines)+'\n'

def allowed_file(scope,path):
    if scope=='home':
        return path in HOME_FILES or (path.startswith('.config/omarchy/plugins/') and len(relpath(path).parts)>4)
    return scope=='system' and (path in SYSTEM_FILES or any(path.startswith(x+'/') for x in SYSTEM_DIRS))

def add_file(folder, entries, scope, relative, source=None, data=None, mode=None, home=None):
    relpath(relative)
    if not allowed_file(scope,relative): raise ValueError(f'File outside capture allowlist: {relative}')
    if source is not None:
        source=pathlib.Path(source)
        if source.is_symlink(): raise ValueError(f'Symlink requires explicit review: {source}')
        if not source.is_file(): return
        data=source.read_bytes();mode=source.stat().st_mode & 0o777
    if len(data)>95*1024*1024: raise ValueError(f'Profile file too large: {relative}')
    asset=relative.startswith('.config/omarchy/plugins/') and (pathlib.Path(relative).suffix.lower() in ASSET_SUFFIXES or data.startswith(b'\x7fELF'))
    if not asset:
        if b'\0' in data: raise ValueError(f'Binary data is not a profile configuration: {relative}')
        text=data.decode('utf-8')
        if SECRET.search(text): raise ValueError(f'Possible credential in {relative}; export refused')
        if home: text=text.replace(str(home),'__HOME__')
        data=text.encode()
    destination=folder/'files'/scope/relative
    destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(data)
    entries.append({'scope':scope,'path':relative,'sha256':digest(data),'mode':mode or 0o644})

def capture_plugins(folder, entries, home, shell, warnings):
    disabled=set(shell.get('disabledPlugins',[]));plugins=[]
    base=home/'.config/omarchy/plugins'
    for path in sorted(base.glob('*')):
        resolved=path.resolve(); manifest=resolved/'manifest.json'
        if not manifest.is_file(): continue
        meta=json.loads(manifest.read_text());pid=meta.get('id',path.name)
        if pid in disabled: continue
        if not re.fullmatch(r'[A-Za-z0-9_.-]+',pid): raise ValueError('Unsafe plugin ID')
        gitroot=execute(['git','-C',resolved,'rev-parse','--show-toplevel'],optional=True).strip()
        origin='';revision='';dirty=False
        if gitroot and pathlib.Path(gitroot).resolve()==resolved:
            origin=execute(['git','-C',resolved,'remote','get-url','origin'],optional=True).strip()
            if origin and not re.fullmatch(r'https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?',origin):
                warnings.append(f'{pid}: private or non-HTTPS origin omitted');origin=''
            revision=execute(['git','-C',resolved,'rev-parse','HEAD']).strip()
            dirty=bool(execute(['git','-C',resolved,'status','--porcelain']))
            names=execute(['git','-C',resolved,'ls-files','-z']).split('\0')
            sources=[resolved/n for n in names if n]
        else:
            sources=[p for p in resolved.rglob('*') if p.is_file() and not any(x.startswith('.') or x in ['node_modules','cache','__pycache__'] for x in p.relative_to(resolved).parts)]
        skipped=[]
        for source in sorted(sources):
            relative=source.relative_to(resolved)
            # Upstream ignore rules must not hide captured payloads from OCP's Git repository.
            if source.name in {'.gitignore','.gitattributes'}: continue
            if any(part in {'tests','testdata','__tests__','.github'} for part in relative.parts): continue
            if not source.exists(): continue
            asset=source.suffix.lower() in ASSET_SUFFIXES or source.read_bytes()[:4]==b'\x7fELF'
            if source.is_symlink() or source.stat().st_size>95*1024*1024 or (not asset and b'\0' in source.read_bytes()[:4096]):
                skipped.append(str(relative));continue
            if not asset:
                try: source.read_text()
                except UnicodeError: skipped.append(str(relative));continue
            add_file(folder,entries,'home',f'.config/omarchy/plugins/{pid}/{relative}',source=source,home=home)
        plugins.append({'id':pid,'version':meta.get('version','unknown'),'origin':origin or None,
                        'revision':revision or None,'modified':dirty,'license':meta.get('license'),
                        'skipped_assets':skipped,'runtime_setup':'Review the captured upstream README for any native runtime setup.'})
        if skipped: warnings.append(f'{pid}: {len(skipped)} binary/symlink assets omitted; see plugin metadata')
    return plugins

def capture(profile_id=None, home=None, system=None, profiles=None, note=''):
    while True:
        try: author=input('Author name: ').strip()
        except EOFError: raise ValueError('Author name is required; capture needs interactive input') from None
        if author and not any(ord(c)<32 or ord(c)==127 for c in author): break
        print('Enter a nonempty author name without control characters.')
    from .software import ask_apps, selection_metadata
    choices=ask_apps()
    home=home or pathlib.Path.home();system=system or pathlib.Path('/');profiles=profiles or ROOT/'profiles'
    hw=hardware(system);profile_id=safe_id(profile_id or slug(hw['vendor']+'-'+hw['model']))
    destination=profiles/profile_id
    if destination.exists(): raise ValueError(f'{profile_id} exists; use a new variant ID to preserve the original')
    profiles.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.ocp-',dir=profiles) as tmp:
        folder=pathlib.Path(tmp);entries=[];warnings=[]
        states,sources=limine_state(system)
        boot={};omitted={};review={}
        for scope,options in states.items(): boot[scope],omitted[scope],review[scope]=classify_options(options)
        shellpath=home/'.config/omarchy/shell.json'
        shell=json.loads(shellpath.read_text()) if shellpath.exists() else {}
        for relative in sorted(HOME_FILES):
            source=home/relative
            if not source.is_file(): continue
            if relative=='.config/brumm/options.json' and not choices['brumm']: continue
            if source.suffix=='.json':
                obj=json.loads(source.read_text())
                if relative=='.config/zapfast/settings.json':
                    keys={'version','theme','font','interface_language','zoom','sidebar_width','enter_sends',
                          'show_shortcut_hints','keep_running_in_background','notifications','voice_speed','pause_other_media'}
                    obj={k:v for k,v in obj.items() if k in keys}
                else: obj=clean_json(obj)
                add_file(folder,entries,'home',relative,data=(json.dumps(obj,indent=2)+'\n').encode(),home=home)
            else: add_file(folder,entries,'home',relative,source=source,home=home)
        for directory in SYSTEM_DIRS:
            for source in sorted((system/directory).glob('*')):
                if source.is_file() and not source.is_symlink():
                    add_file(folder,entries,'system',str(source.relative_to(system)),source=source,home=home)
        for relative in SYSTEM_FILES:
            source=system/relative
            if source.is_file(): add_file(folder,entries,'system',relative,source=source,home=home)
        installed={line.split(' ',1)[0]:line.split(' ',1)[1] for line in execute(['pacman','-Q'],optional=True).splitlines() if ' ' in line}
        foreign=set(execute(['pacman','-Qqm'],optional=True).splitlines())
        packages=[{'name':name,'version':installed.get(name),'provider':'aur' if name in foreign else 'pacman'} for name in sorted(HARDWARE_PACKAGES & installed.keys())]
        software=[{'id':app,'provider':'arch-package','package':pkg,'captured_version':installed.get(pkg),'installed':pkg in installed} for app,pkg in APP_PACKAGES.items()]
        software.append({'id':'bruno','provider':'flatpak','remote':'flathub','ref':'com.usebruno.Bruno//stable'})
        brumm=home/'.local/bin/brumm'
        if not brumm.exists(): brumm=pathlib.Path(shutil.which('brumm') or '/nonexistent-ocp-brumm')
        version=execute([brumm,'version'],optional=True).strip() if choices['brumm'] and brumm.exists() else ''
        match=re.search(r'\bv(\d+\.\d+\.\d+)\b',version)
        software.append({'id':'brumm','provider':'github-release','repository':'chriopter/brumm',
                         'tag':'v'+match.group(1) if match else None,'asset':'brumm-linux-amd64.tar.gz' if hw['architecture']=='x86_64' else None,
                         'sha256':None})
        if choices['brumm'] and brumm.exists() and not match:
            raise ValueError('Cannot determine the installed brumm version; refusing to substitute latest')
        software=[selection_metadata(app,choices) for app in software]
        plugins=capture_plugins(folder,entries,home,shell,warnings)
        if not choices['brumm'] and any(p['id']=='chriopter.brumm' for p in plugins):
            warnings.append('The captured brumm plugin requires the brumm application, which was excluded.')
        services=[name for name in sorted(SERVICES) if any((system/'etc/systemd/system').glob(f'*.wants/{name}'))]
        if any(x['path']=='etc/mbpfan.conf' for x in entries): warnings.append('Verify fan RPM limits against target applesmc hardware before applying.')
        if any(review.values()): warnings.append('Unclassified kernel options were recorded for review and are not applied.')
        data={'schema_version':1,'id':profile_id,'author':author,'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'description':note or f'Community hardware profile for {hw["vendor"]} {hw["model"]}',
              'hardware':hw,'environment':{'omarchy':installed.get('omarchy'),'hyprland':installed.get('hyprland'),'kernel':platform.release()},
              'validation':{'status':'captured','tested_on_other_machine':False,'notes':[]},
              'boot':{'loader':'limine','sources':sources,'hardware_options':boot,'omitted_keys':omitted,'review_only':review},
              'hardware_packages':packages,'services':services,'software':software,'plugins':plugins,
              'plugin_detection':'All installed user plugins except disabledPlugins; built-ins remain supplied by Omarchy.',
              'files':sorted(entries,key=lambda x:(x['scope'],x['path'])),'warnings':warnings}
        (folder/'profile.json').write_text(json.dumps(data,indent=2)+'\n')
        from .apply import lock
        print('Verifying and pinning selected applications…',flush=True)
        try: lock(folder)
        except (OSError, ValueError) as error:
            raise ValueError(f'Capture could not pin selected applications: {error}. No profile was created; retry capture when resolved.') from error
        data=json.loads((folder/'profile.json').read_text())
        warnings=data['warnings']
        (folder/'README.md').write_text(f'# {hw["vendor"]} {hw["model"]}\n\n{data["description"]}\n\nAuthor: {author}\n\nStatus: captured; not independently tested.\n\n'+
            '## Contributor verification\n\nRecord display, audio, network, Bluetooth, suspend/resume, fan and boot results here.\n\n'+
            '## Capture warnings\n\n'+'\n'.join('- '+w for w in warnings)+'\n')
        validate(folder);folder.rename(destination)
    return destination

def load_manifest(folder):
    """Read and check manifest metadata without opening profile payload files."""
    if folder.is_symlink(): raise ValueError('Profile directory must not be a symlink')
    p=folder/'profile.json'
    if p.is_symlink(): raise ValueError('Profile manifest must not be a symlink')
    m=json.loads(p.read_text())
    required={'schema_version','id','created_at','description','hardware','environment','validation','boot','hardware_packages','services','software','plugins','plugin_detection','files','warnings'}
    if not isinstance(m,dict) or not required <= set(m) or set(m)-required-{'author'}: raise ValueError('Invalid profile manifest fields')
    if 'author' in m and (not isinstance(m['author'],str) or not m['author'].strip() or any(ord(c)<32 or ord(c)==127 for c in m['author'])):
        raise ValueError('Author must be a nonempty name without control characters')
    for key in ['hardware_packages','services','software','plugins','files','warnings']:
        if not isinstance(m[key],list): raise ValueError(f'Expected array: {key}')
    if m['validation'].get('status') not in ['captured','locally-tested','model-verified']: raise ValueError('Invalid validation status')
    if m.get('schema_version')!=1: raise ValueError('Unsupported profile schema')
    if safe_id(m['id'])!=folder.name and not folder.name.startswith('.ocp-'): raise ValueError('Profile ID/directory mismatch')
    if not isinstance(m['hardware']['pci'],list): raise ValueError('Missing PCI inventory')
    if m['validation'].get('status')=='model-verified' and m['validation'].get('tested_on_other_machine') is not True:
        raise ValueError('Model verification requires another-machine testing')
    return m

def validate(folder):
    m=load_manifest(folder)
    for scope,options in m['boot']['hardware_options'].items():
        if not re.fullmatch(r'[A-Za-z0-9_.+*-]+',scope): raise ValueError('Invalid Limine scope')
        portable,omitted,review=classify_options(options)
        if omitted or review or portable!=options: raise ValueError('Nonportable kernel option in hardware_options')
        if any(any(c in option for c in ['\n','\r','"',"'",'$','`','\\']) for option in options): raise ValueError('Unsafe kernel option')
    seen=set()
    for f in m['files']:
        relative=str(relpath(f['path'])); key=(f['scope'],relative)
        if key in seen or not allowed_file(*key): raise ValueError(f'Invalid/duplicate destination: {key}')
        seen.add(key);source=folder/'files'/f['scope']/relative
        if any(p.is_symlink() for p in [source,*source.parents] if p!=folder.parent): raise ValueError('Symlink in profile payload')
        data=source.read_bytes()
        if digest(data)!=f['sha256']: raise ValueError(f'Checksum mismatch: {relative}')
        if SECRET.search(data.decode(errors='replace')): raise ValueError(f'Credential pattern found: {relative}')
        if not isinstance(f['mode'],int) or f['mode'] & ~0o777: raise ValueError('Invalid file mode')
    if {a.get('id') for a in m['software']}!={*APP_PACKAGES,'bruno','brumm'} or len(m['software'])!=6:
        raise ValueError('Software must contain exactly the six standard OCP applications')
    for package in m['hardware_packages']:
        if not re.fullmatch(r'[a-z0-9][a-z0-9@._+-]*',package['name']): raise ValueError('Invalid package name')
        if package['name'] not in HARDWARE_PACKAGES: raise ValueError('Unsupported hardware package')
        if package['provider'] not in ['pacman','aur']: raise ValueError('Invalid package provider')
    if set(m['services'])-SERVICES: raise ValueError('Unsupported hardware service')
    for plugin in m['plugins']:
        if not re.fullmatch(r'[A-Za-z0-9_.-]+',plugin['id']): raise ValueError('Invalid plugin ID')
    from .software import validate_pin
    for app in m['software']:
        for flag in ['included','requested']:
            if flag in app and not isinstance(app[flag],bool): raise ValueError('Invalid application selection')
        validate_pin(app,m['hardware']['architecture'])
        if app['id'] not in {*APP_PACKAGES,'bruno','brumm'}: raise ValueError('Unknown software recipe')
        if app['id'] in APP_PACKAGES and app.get('package')!=APP_PACKAGES[app['id']]: raise ValueError('Modified app recipe')
        if app['id']=='bruno' and app.get('provider')!='github-appimage' and (app.get('remote')!='flathub' or app.get('ref')!='com.usebruno.Bruno//stable'): raise ValueError('Modified Bruno recipe')
        if app['id']=='bruno' and app.get('provider')=='github-appimage' and (app.get('repository')!='usebruno/bruno' or app.get('pin',{}).get('kind')!='appimage'):
            raise ValueError('Modified Bruno AppImage recipe')
        if app['id']=='brumm':
            if app.get('repository')!='chriopter/brumm': raise ValueError('Modified brumm origin')
            if app.get('tag') is not None and not re.fullmatch(r'v\d+\.\d+\.\d+',app['tag']): raise ValueError('Invalid brumm tag')
            if app.get('asset') not in [None,'brumm-linux-amd64.tar.gz','brumm-linux-arm64.tar.gz']: raise ValueError('Invalid brumm asset')
            if app.get('sha256') is not None and not re.fullmatch(r'[0-9a-f]{64}',app['sha256']): raise ValueError('Invalid brumm digest')
    apps_by_id={a['id']:a for a in m['software']}
    bruno=apps_by_id['bruno'];flatpak=apps_by_id['flatpak']
    if bruno.get('included',True) and bruno.get('provider')!='github-appimage' and not flatpak.get('included',True):
        raise ValueError('Selected Flathub Bruno requires Flatpak in the profile')
    actual={str(p.relative_to(folder/'files')) for p in (folder/'files').rglob('*') if p.is_file()}
    expected={f"{x['scope']}/{x['path']}" for x in m['files']}
    if actual!=expected: raise ValueError('Unmanifested or missing profile files')
    return m
