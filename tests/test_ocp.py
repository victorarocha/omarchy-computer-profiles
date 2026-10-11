import json, pathlib, tempfile, unittest
from unittest.mock import patch
from ocp_lib.core import (classify_options, merge_options, parse_limine, render_limine, capture,
                          validate, hardware, safe_id, add_file, digest)
from ocp_lib.apply import Transaction, restore, match_hardware, install_brumm

class BootTests(unittest.TestCase):
    def test_no_source_disk_identity_export(self):
        portable,omitted,review=classify_options(['root=UUID=SOURCE','cryptdevice=PARTUUID=SECRET:root','resume=/dev/nvme0n1','amdgpu.dpm=0','pcie_aspm=off','secret_token=private','quiet'])
        self.assertEqual(portable,['amdgpu.dpm=0','pcie_aspm=off'])
        self.assertNotIn('SOURCE',str(omitted));self.assertNotIn('SECRET',str(omitted))
        self.assertNotIn('private',str(review))
    def test_literal_scopes_and_append(self):
        text='KERNEL_CMDLINE[default]="root=UUID=TARGET rw"\nKERNEL_CMDLINE[default]+=amdgpu.dpm=0\nKERNEL_CMDLINE[linux-lts]=root=UUID=OTHER quiet'
        result=parse_limine(text)
        self.assertEqual(result['default'],['root=UUID=TARGET','rw','amdgpu.dpm=0'])
        self.assertEqual(result['linux-lts'][0],'root=UUID=OTHER')
    def test_never_execute_dynamic_configuration(self):
        for text in ['KERNEL_CMDLINE[default]="$(touch /tmp/evil)"','KERNEL_CMDLINE[default]=$OPTIONS','KERNEL_CMDLINE[default]=`id`']:
            with self.assertRaises(ValueError): parse_limine(text)
    def test_merge_preserves_target_boot_identity_and_replaces_conflicts(self):
        target={'default':['root=UUID=TARGET','cryptdevice=UUID=TARGET:root','rw','amdgpu.dpm=1']}
        text=render_limine('ESP_PATH="/boot"',target,{'default':['amdgpu.dpm=0']})
        parsed=parse_limine(text)
        self.assertIn('root=UUID=TARGET',parsed['default']);self.assertIn('cryptdevice=UUID=TARGET:root',parsed['default'])
        self.assertNotIn('amdgpu.dpm=1',parsed['default']);self.assertIn('amdgpu.dpm=0',parsed['default'])
        self.assertEqual(text,render_limine(text,parse_limine(text),{'default':['amdgpu.dpm=0']}))
    def test_spaced_acpi_option_round_trip(self):
        text=render_limine('',{'default':['root=UUID=TARGET']},{'default':['acpi_osi=Windows 2020']})
        self.assertEqual(parse_limine(text)['default'][-1],'acpi_osi=Windows 2020')
        self.assertIn('acpi_osi=\\"Windows 2020\\"',text)
    def test_missing_root_refused(self):
        with self.assertRaises(ValueError): render_limine('',{'default':['quiet']},{'default':['pcie_aspm=off']})

class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.base=pathlib.Path(self.tmp.name);self.home=self.base/'home';self.system=self.base/'sysroot';self.profiles=self.base/'profiles'
        for rel,text in {'sys/class/dmi/id/sys_vendor':'Example','sys/class/dmi/id/product_name':'Model 1','sys/class/dmi/id/board_name':'Board','etc/default/limine':'KERNEL_CMDLINE[default]="root=UUID=PRIVATE amdgpu.dpm=0"','etc/modprobe.d/audio.conf':'options snd_hda_intel model=auto'}.items():
            p=self.system/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
        p=self.home/'.config/zapfast/settings.json';p.parent.mkdir(parents=True);p.write_text(json.dumps({'theme':'dark','last_chat':'private','giphy_key':'private','proxy':'private'}))
        p=self.home/'.config/omarchy/shell.json';p.parent.mkdir(parents=True);p.write_text(json.dumps({'disabledPlugins':['disabled'],'plugins':[{'id':'active','apiKey':'private'}]}))
        for name in ['active','disabled']:
            p=self.home/'.config/omarchy/plugins'/name;p.mkdir(parents=True)
            (p/'manifest.json').write_text(json.dumps({'id':name,'version':'1.0','license':'MIT'}));(p/'Panel.qml').write_text('Item {}')
            (p/'preview.png').write_bytes(b'\x89PNG\x00image')
        self.release_lock=patch('ocp_lib.apply.lock');self.release_lock.start()
        self.addCleanup(self.release_lock.stop)
        self.author_prompt=patch('builtins.input',return_value='Test Author');self.author_prompt.start()
        self.addCleanup(self.author_prompt.stop)
        self.patcher=patch('ocp_lib.core.execute',return_value='');self.patcher.start()
    def tearDown(self): self.patcher.stop();self.tmp.cleanup()
    def capture(self): return capture('example-model',self.home,self.system,self.profiles)
    def test_capture_verifies_release_before_publishing_profile(self):
        # Exercise the real verification logic, with deterministic public-release responses.
        self.release_lock.stop()
        from ocp_lib.apply import lock as real_lock
        blob=b'verified release archive';checksum=digest(blob)
        def verify(folder):
            self.assertFalse((self.profiles/'example-model').exists())
            m=json.loads((folder/'profile.json').read_text())
            app=next(x for x in m['software'] if x['id']=='brumm')
            app.update(tag='v1.0.1',asset='brumm-linux-amd64.tar.gz')
            (folder/'profile.json').write_text(json.dumps(m))
            metadata={'assets':[{'name':app['asset'],'browser_download_url':f"https://github.com/chriopter/brumm/releases/download/{app['tag']}/{app['asset']}",'digest':'sha256:'+checksum}]}
            with patch('ocp_lib.apply.download',side_effect=[json.dumps(metadata).encode(),blob]): real_lock(folder)
        with patch('ocp_lib.apply.lock',side_effect=verify) as lock_call:
            folder=self.capture()
        lock_call.assert_called_once()
        m=validate(folder)
        self.assertEqual(next(x for x in m['software'] if x['id']=='brumm')['sha256'],checksum)
        self.assertFalse(any('ocp lock' in w for w in m['warnings']))
        self.assertNotIn('ocp lock',(folder/'README.md').read_text())
    def test_capture_verification_failure_does_not_publish_profile(self):
        with patch('ocp_lib.apply.lock',side_effect=ValueError('Release asset checksum mismatch')):
            with self.assertRaisesRegex(ValueError,'Capture could not verify brumm release'): self.capture()
        self.assertFalse((self.profiles/'example-model').exists())
        self.assertEqual(list(self.profiles.iterdir()),[])
    def test_author_prompt_retries_blank_and_records_trimmed_name(self):
        with patch('builtins.input',side_effect=['', '  ', '  Ada Lovelace  ']) as prompt:
            folder=self.capture()
        self.assertEqual(prompt.call_count,3)
        self.assertEqual(validate(folder)['author'],'Ada Lovelace')
        self.assertIn('Author: Ada Lovelace',(folder/'README.md').read_text())
    def test_author_required_when_input_unavailable(self):
        with patch('builtins.input',side_effect=EOFError), self.assertRaisesRegex(ValueError,'Author name is required'):
            self.capture()
        self.assertFalse(self.profiles.exists())
    def test_legacy_profiles_and_list_author(self):
        import io,sys
        from ocp_lib.__main__ import main
        folder=self.capture()
        output=io.StringIO()
        with patch('ocp_lib.__main__.ROOT',self.base), patch.object(sys,'argv',['ocp','list']), patch('sys.stdout',output): main()
        self.assertIn('AUTHOR',output.getvalue());self.assertIn('Test Author',output.getvalue())
        m=json.loads((folder/'profile.json').read_text());m.pop('author');(folder/'profile.json').write_text(json.dumps(m))
        validate(folder)
        output=io.StringIO()
        with patch('ocp_lib.__main__.ROOT',self.base), patch.object(sys,'argv',['ocp','list']), patch('sys.stdout',output): main()
        self.assertIn('Unknown',output.getvalue())
    def test_capture_is_private_and_contains_active_plugins_assets_and_software(self):
        folder=self.capture();m=validate(folder)
        self.assertEqual([p['id'] for p in m['plugins']],['active'])
        self.assertEqual({x['id'] for x in m['software']},{'zapfast','flatpak','bruno','brumm','google-chrome','obsidian'})
        self.assertNotIn('PRIVATE',(folder/'profile.json').read_text())
        settings=json.loads((folder/'files/home/.config/zapfast/settings.json').read_text());self.assertEqual(settings,{'theme':'dark'})
        self.assertTrue((folder/'files/home/.config/omarchy/plugins/active/preview.png').exists())
        shell=(folder/'files/home/.config/omarchy/shell.json').read_text();self.assertNotIn('apiKey',shell)
    def test_existing_profile_not_overwritten(self):
        self.capture()
        with self.assertRaises(ValueError): self.capture()
    def test_checksums_detect_tampering(self):
        folder=self.capture();(folder/'files/system/etc/modprobe.d/audio.conf').write_text('modified')
        with self.assertRaisesRegex(ValueError,'Checksum'): validate(folder)
    def test_manifest_path_traversal_refused(self):
        folder=self.capture();m=json.loads((folder/'profile.json').read_text());m['files'][0]['path']='../../etc/passwd'
        (folder/'profile.json').write_text(json.dumps(m))
        with self.assertRaises(ValueError): validate(folder)
    def test_payload_symlink_refused(self):
        folder=self.capture();p=folder/'files/system/etc/modprobe.d/audio.conf';p.unlink();p.symlink_to('/etc/passwd')
        with self.assertRaises(ValueError): validate(folder)
    def test_credentials_refused(self):
        p=self.home/'.config/hypr/input.lua';p.parent.mkdir(parents=True);p.write_text('-----BEGIN RSA PRIVATE KEY-----')
        with self.assertRaisesRegex(ValueError,'credential'): self.capture()
        self.assertFalse((self.profiles/'example-model').exists())
    def test_invalid_kernel_profile_refused(self):
        folder=self.capture();m=json.loads((folder/'profile.json').read_text());m['boot']['hardware_options']['default'].append('root=UUID=SOURCE')
        (folder/'profile.json').write_text(json.dumps(m))
        with self.assertRaises(ValueError): validate(folder)
    def test_missing_software_recipe_refused(self):
        folder=self.capture();m=json.loads((folder/'profile.json').read_text());m['software'].pop()
        (folder/'profile.json').write_text(json.dumps(m))
        with self.assertRaises(ValueError): validate(folder)
    def test_model_verified_status_requires_second_machine(self):
        folder=self.capture();m=json.loads((folder/'profile.json').read_text());m['validation']['status']='model-verified'
        (folder/'profile.json').write_text(json.dumps(m))
        with self.assertRaises(ValueError): validate(folder)
    def test_hardware_matching(self):
        m=validate(self.capture());h=hardware(self.system);match_hardware(m,h)
        h['model']='Different'
        with self.assertRaises(ValueError): match_hardware(m,h)
    def test_model_variant_needs_explicit_override(self):
        m=validate(self.capture());h=hardware(self.system);h['pci']=[{'vendor':'0x1002','device':'0x1234','class':'0x030000'}]
        with self.assertRaises(ValueError): match_hardware(m,h)
        match_hardware(m,h,True)

class RestoreTests(unittest.TestCase):
    def test_atomic_install_and_restore_existing_and_new_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=pathlib.Path(tmp)
            with patch('pathlib.Path.home',return_value=home):
                original=home/'.config/hypr/input.lua';original.parent.mkdir(parents=True);original.write_text('before');original.chmod(0o600)
                new=home/'.config/hypr/monitors.lua'
                tx=Transaction(home,'example');tx.put(original,b'after',0o644);tx.put(new,b'new',0o644)
                self.assertEqual(original.read_text(),'after')
                restore(tx.folder,False);self.assertEqual(original.read_text(),'after')
                restore(tx.folder,True);self.assertEqual(original.read_text(),'before');self.assertEqual(original.stat().st_mode&0o777,0o600);self.assertFalse(new.exists())
    def test_symlink_destination_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=pathlib.Path(tmp)
            with patch('pathlib.Path.home',return_value=home):
                target=home/'link';target.symlink_to('/etc/passwd');tx=Transaction(home,'example')
                with self.assertRaises(ValueError): tx.put(target,b'no',0o644)
    def test_brumm_digest_checked_before_extract_or_write(self):
        with patch('ocp_lib.apply.download',return_value=b'tampered'):
            with self.assertRaisesRegex(ValueError,'checksum'): install_brumm({'tag':'v1.0.1','asset':'brumm-linux-amd64.tar.gz','sha256':'0'*64},None,pathlib.Path('/tmp'))

if __name__=='__main__': unittest.main()
