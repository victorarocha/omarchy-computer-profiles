# Contributing hardware profiles

1. Begin with a working, updated Omarchy installation.
2. Capture a profile with a meaningful model/variant ID and description.
3. Run `ocp lock`, `ocp validate` and inspect the preview.
4. Review all included files, kernel options, licenses and capture warnings.
5. Apply to another computer with matching hardware when possible.
6. Record actual results in the profile README and `validation.notes`.
7. Submit the profile through a pull request with exact versions tested.

Use `validation.status: "captured"` for an untested export, `"locally-tested"`
when applied successfully on its source computer, and `"model-verified"` only
after successful tests on another computer of that model/variant. Set
`tested_on_other_machine` truthfully. This is contributor reporting, not OCP
certification; reviewers should request evidence appropriate to the deployment.

Record results for:

- Cold boot and reboot, including selected kernel and Limine options.
- Display outputs, scaling, GPU acceleration and any multi-GPU limitations.
- Ethernet, Wi-Fi and Bluetooth.
- Audio input/output and connected peripherals.
- Suspend/resume, fans and temperature behavior.
- Active plugins and any separate runtime setup they require.
- Launching all six standard applications; account sign-in is user-specific.
- Backups and recovery on the test machine.

Profile paths are `profiles/<id>/profile.json`, `README.md` and
`files/{home,system}/<relative destination>`. The manifest records SHA-256,
permissions and destination scope for every payload file. Do not edit a payload
without updating its checksum; use `python3` with hashlib or `sha256sum`, then
validate again. Only the reviewed path/recipe allowlists are accepted. New
hardware options or file locations require a code change and tests.

Keep a distinct ID for incompatible GPU/network variants. Do not overwrite a
working profile with an untested update. Never contribute usernames, hostnames,
disk UUIDs, MAC addresses, serials, account state or credentials. Scrutinize custom
rules and comments. Preserve third-party license and attribution files.
