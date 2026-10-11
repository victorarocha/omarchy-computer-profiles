import base64, io, json, pathlib, tarfile, tempfile, unittest
from unittest.mock import patch, Mock
from ocp_lib.core import digest
from ocp_lib.software import (ask_apps, OPTIONAL_APPS, brumm_pin, bruno_pin, package_pin,
                              repositories, database_entries, resolve_apps, validate_pin)
from ocp_lib.apply import install_pinned_packages, install_bruno, apply

class PromptTests(unittest.TestCase):
    def test_one_prompt_per_app_and_independent_answers(self):
        with patch('builtins.input',side_effect=['yes','N','y','no']) as question:
            choices=ask_apps()
        self.assertEqual(choices,{'brumm':True,'flatpak':False,'google-chrome':True,'bruno':False})
        self.assertEqual(question.call_count,4)
        self.assertEqual([x.args[0] for x in question.call_args_list],[
            'Include brumm? [y/n]: ','Include Flatpak? [y/n]: ',
            'Include Google Chrome? [y/n]: ','Include Bruno? [y/n]: '])
    def test_invalid_answer_retried(self):
        with patch('builtins.input',side_effect=['','maybe','yes','no','no','no']):
            self.assertTrue(ask_apps()['brumm'])
    def test_eof_is_an_error(self):
        with patch('builtins.input',side_effect=EOFError), self.assertRaises(ValueError): ask_apps()

class BrummTests(unittest.TestCase):
    def release(self,tag,arch='amd64',blob=b'release',**flags):
        name=f'brumm-linux-{arch}.tar.gz'
        return {'tag_name':tag,'assets':[{'name':name,'digest':'sha256:'+digest(blob),
                'browser_download_url':f'https://github.com/chriopter/brumm/releases/download/{tag}/{name}'}],**flags}
    def test_installed_release_is_retained(self):
        fetch=Mock(side_effect=[json.dumps(self.release('v1.0.1')).encode(),b'release'])
        pin=brumm_pin({'tag':'v1.0.1'},'x86_64',fetch)
        self.assertEqual(pin['version'],'v1.0.1');self.assertEqual(pin['source'],'installed')
        self.assertTrue(fetch.call_args_list[0].args[0].endswith('/tags/v1.0.1'))
    def test_missing_app_uses_latest_stable_compatible_release(self):
        releases=[self.release('v3.0.0',prerelease=True),self.release('v2.0.0',arch='arm64'),self.release('v1.5.0')]
        fetch=Mock(side_effect=[json.dumps(releases).encode(),b'release'])
        pin=brumm_pin({},'x86_64',fetch)
        self.assertEqual(pin['version'],'v1.5.0');self.assertEqual(pin['source'],'latest')
    def test_installed_release_with_no_asset_does_not_fall_forward(self):
        fetch=Mock(return_value=json.dumps(self.release('v1.0.1',arch='arm64')).encode())
        with self.assertRaises(ValueError): brumm_pin({'tag':'v1.0.1'},'x86_64',fetch)
        self.assertEqual(fetch.call_count,1)
    def test_bad_hash_is_rejected(self):
        fetch=Mock(side_effect=[json.dumps(self.release('v1.0.1')).encode(),b'tampered'])
        with self.assertRaisesRegex(ValueError,'checksum'): brumm_pin({'tag':'v1.0.1'},'x86_64',fetch)

class PackageTests(unittest.TestCase):
    def entry(self,name='flatpak',version='1:1.18.2-1'):
        return {'NAME':name,'VERSION':version,'ARCH':'x86_64',
                'FILENAME':f'{name}-{version}-x86_64.pkg.tar.zst','SHA256SUM':digest(b'package'),
                'PGPSIG':base64.b64encode(b'signature').decode()}
    def test_installed_version_is_pinned_exactly(self):
        app={'id':'flatpak','package':'flatpak','captured_version':'1:1.18.2-1'};fetch=Mock()
        with patch('ocp_lib.software.package_metadata',return_value=(self.entry(),'https://mirror.example/extra')):
            pin=package_pin(app,'x86_64',pathlib.Path('/'),fetch)
        self.assertEqual(pin['version'],'1:1.18.2-1');self.assertEqual(pin['source'],'installed');fetch.assert_not_called()
        app['pin']=pin;validate_pin(app,'x86_64')
    def test_missing_app_uses_fresh_repository_version(self):
        app={'id':'flatpak','package':'flatpak','captured_version':None}
        with patch('ocp_lib.software.package_metadata',return_value=(self.entry(version='1:1.20.0-1'),'https://mirror.example/extra')) as metadata:
            pin=package_pin(app,'x86_64',pathlib.Path('/'),Mock())
        self.assertTrue(metadata.call_args.kwargs['latest']);self.assertEqual(pin['version'],'1:1.20.0-1');self.assertEqual(pin['source'],'latest')
    def test_installed_unavailable_chrome_is_not_replaced_with_latest(self):
        app={'id':'google-chrome','package':'google-chrome','captured_version':'100.0-1'}
        with tempfile.TemporaryDirectory() as tmp, patch('ocp_lib.software.package_metadata',return_value=(self.entry('google-chrome','200.0-1'),'https://mirror.example/omarchy')):
            with self.assertRaisesRegex(ValueError,'Cannot pin installed'): package_pin(app,'x86_64',pathlib.Path(tmp),Mock())
    def test_installed_cached_version_is_retained(self):
        app={'id':'google-chrome','package':'google-chrome','captured_version':'100.0-1'}
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);cache=root/'var/cache/pacman/pkg';cache.mkdir(parents=True)
            package=cache/'google-chrome-100.0-1-x86_64.pkg.tar.zst';package.write_bytes(b'old package');(cache/(package.name+'.sig')).write_bytes(b'sig')
            with patch('ocp_lib.software.package_metadata',return_value=(self.entry('google-chrome','200.0-1'),'https://mirror.example/omarchy')),patch('ocp_lib.software.execute',return_value='google-chrome 100.0-1'):
                pin=package_pin(app,'x86_64',root,Mock())
            self.assertEqual(pin['version'],'100.0-1');self.assertEqual(pin['sha256'],digest(b'old package'))
    def test_reused_mirrorlist_applies_to_every_repository(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);(root/'etc/pacman.d').mkdir(parents=True)
            (root/'etc/pacman.conf').write_text('[core]\nInclude = /etc/pacman.d/mirrorlist\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n')
            (root/'etc/pacman.d/mirrorlist').write_text('Server = https://mirror.example/$repo/os/$arch\n')
            self.assertEqual(repositories(root,'x86_64'),{'core':['https://mirror.example/core/os/x86_64'],'extra':['https://mirror.example/extra/os/x86_64']})
    def test_repository_database_fields(self):
        stream=io.BytesIO()
        with tarfile.open(fileobj=stream,mode='w:gz') as archive:
            blob=b'%NAME%\nflatpak\n\n%VERSION%\n1:1.18.2-1\n';info=tarfile.TarInfo('flatpak-1.18.2/desc');info.size=len(blob);archive.addfile(info,io.BytesIO(blob))
        self.assertEqual(list(database_entries(stream.getvalue())),[{'NAME':'flatpak','VERSION':'1:1.18.2-1'}])
    def test_tampered_pin_version_is_rejected(self):
        app={'id':'flatpak','package':'flatpak','captured_version':'1:1.18.2-1'}
        with patch('ocp_lib.software.package_metadata',return_value=(self.entry(),'https://mirror.example/extra')):
            app['pin']=package_pin(app,'x86_64',pathlib.Path('/'),Mock())
        app['pin']['version']='99.0-1'
        with self.assertRaises(ValueError): validate_pin(app,'x86_64')

class BrunoTests(unittest.TestCase):
    def test_installed_flatpak_commit_is_pinned(self):
        def cli(args,**kwargs):
            if '--show-commit' in args and '--user' in args: return 'a'*64+'\n'
            if '--show-origin' in args: return 'flathub\n'
            return ''
        fetch=Mock()
        with patch('ocp_lib.software.execute',side_effect=cli): pin=bruno_pin('x86_64',fetch)
        self.assertEqual(pin['commit'],'a'*64);self.assertEqual(pin['source'],'installed');fetch.assert_not_called()
    def test_missing_bruno_pins_latest_architecture_ref(self):
        fetch=Mock(return_value=('b'*64+'\n').encode())
        with patch('ocp_lib.software.execute',return_value=''): pin=bruno_pin('aarch64',fetch)
        self.assertEqual(pin['commit'],'b'*64);self.assertEqual(pin['source'],'latest')
        self.assertIn('/aarch64/stable',fetch.call_args.args[0])
    def test_native_bruno_retains_installed_application_version(self):
        def cli(args,**kwargs): return 'bruno 4.2.1-1' if args==['pacman','-Q','bruno'] else ''
        asset='bruno_4.2.1_x86_64_linux.AppImage';url=f'https://github.com/usebruno/bruno/releases/download/v4.2.1/{asset}'
        fetch=Mock(return_value=json.dumps({'assets':[{'name':asset,'browser_download_url':url,'digest':'sha256:'+'a'*64}]}).encode())
        with patch('ocp_lib.software.execute',side_effect=cli): pin=bruno_pin('x86_64',fetch)
        self.assertEqual(pin['version'],'4.2.1');self.assertEqual(pin['source'],'installed');self.assertEqual(pin['kind'],'appimage')
    def test_bruno_runtime_dependency_is_visible_and_pinned(self):
        manifest={'hardware':{'architecture':'x86_64'},'warnings':[],'software':[
            {'id':'bruno','included':True,'requested':True},
            {'id':'flatpak','package':'flatpak','included':False,'requested':False}]}
        with patch('ocp_lib.software.bruno_pin',return_value={'architecture':'x86_64','commit':'a'*64,'source':'latest'}),patch('ocp_lib.software.package_pin',return_value={'version':'1.0','source':'latest'}) as package:
            result=resolve_apps(manifest,Mock())
        flatpak=result['software'][1];self.assertTrue(flatpak['included']);self.assertEqual(flatpak['dependency_for'],['bruno']);package.assert_called_once()
    def test_existing_pins_do_not_advance_on_lock(self):
        pin={'version':'v1.0.1','architecture':'x86_64','source':'installed'}
        manifest={'hardware':{'architecture':'x86_64'},'warnings':[],'software':[{'id':'brumm','pin':pin}]}
        fetch=Mock();result=resolve_apps(manifest,fetch)
        self.assertEqual(result['software'][0]['pin'],pin);fetch.assert_not_called()
    def test_native_bruno_does_not_force_flatpak(self):
        manifest={'hardware':{'architecture':'x86_64'},'warnings':[],'software':[
            {'id':'bruno','included':True,'requested':True},
            {'id':'flatpak','package':'flatpak','included':True,'requested':False}]}
        with patch('ocp_lib.software.bruno_pin',return_value={'architecture':'x86_64','version':'4.2.1','source':'installed','kind':'appimage'}),patch('ocp_lib.software.package_pin') as package:
            result=resolve_apps(manifest,Mock())
        self.assertFalse(result['software'][1]['included']);package.assert_not_called()
    def test_all_excluded_apps_are_not_resolved(self):
        manifest={'hardware':{'architecture':'x86_64'},'warnings':[],'software':[{'id':name,'included':False} for name in OPTIONAL_APPS]}
        fetch=Mock()
        resolve_apps(manifest,fetch);fetch.assert_not_called()

class InstallTests(unittest.TestCase):
    def test_package_hash_failure_prevents_installation(self):
        app={'id':'flatpak','package':'flatpak','pin':{'url':'https://example/p.pkg.tar.zst','sha256':'0'*64}}
        with patch('ocp_lib.apply.download',return_value=b'tampered'),patch('ocp_lib.apply.command') as command:
            with self.assertRaisesRegex(ValueError,'checksum'): install_pinned_packages([app])
        command.assert_not_called()
    def test_pinned_package_identity_is_checked_and_signature_verified(self):
        app={'id':'flatpak','package':'flatpak','pin':{'url':'https://example/flatpak-1.0-1-x86_64.pkg.tar.zst','version':'1.0-1','sha256':digest(b'package'),'signature':base64.b64encode(b'signature').decode()}}
        with patch('ocp_lib.apply.download',return_value=b'package'),patch('ocp_lib.apply.execute',return_value='flatpak 1.0-1'),patch('ocp_lib.apply.command') as command:
            install_pinned_packages([app],True)
        self.assertEqual(command.call_args_list[0].args[0][:2],['pacman-key','--verify'])
        self.assertEqual(command.call_args_list[1].args[0][:3],['sudo','pacman','-U'])
    def test_bruno_deploys_and_verifies_pinned_commit(self):
        app={'pin':{'architecture':'x86_64','commit':'a'*64}}
        with patch('ocp_lib.apply.command') as command,patch('ocp_lib.apply.execute',return_value='a'*64): install_bruno(app,True)
        self.assertIn('--commit='+'a'*64,command.call_args_list[-1].args[0])
    def test_software_apply_does_not_install_excluded_apps(self):
        manifest={'id':'example','warnings':[],'files':[],'software':[
            {'id':app,'included':False} for app in OPTIONAL_APPS]+[
            {'id':'zapfast','package':'zapfast-bin'},{'id':'obsidian','package':'obsidian'}]}
        with patch('ocp_lib.apply.validate',return_value=manifest),patch('ocp_lib.apply.os.geteuid',return_value=1000),patch('ocp_lib.apply.shutil.which',return_value='/usr/bin/tool'),patch('ocp_lib.apply.hardware',return_value={}),patch('ocp_lib.apply.match_hardware'),patch('ocp_lib.apply.Transaction'),patch('ocp_lib.apply.execute',return_value='exists'),patch('ocp_lib.apply.command') as command,patch('ocp_lib.apply.install_bruno') as bruno,patch('ocp_lib.apply.install_brumm') as brumm,patch('ocp_lib.apply.install_pinned_packages') as packages:
            apply(pathlib.Path('/unused'),{'software'},True)
        bruno.assert_not_called();brumm.assert_not_called();packages.assert_called_once_with([],False)
        args=command.call_args.args[0];self.assertIn('zapfast-bin',args);self.assertIn('obsidian',args)
        for name in ['flatpak','google-chrome','brumm','com.usebruno.Bruno']: self.assertNotIn(name,args)

if __name__=='__main__': unittest.main()
