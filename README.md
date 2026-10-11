# Omarchy Computer Profiles (OCP)

Share working Omarchy configurations by computer model. OCP helps individuals
keep older hardware useful and helps companies build a reviewed catalogue of
profiles for their fleets.

A profile records hardware compatibility, portable Limine kernel options,
selected driver configuration, enabled user plugins, and a common software set:
**ZapFast, brumm, Flatpak, Bruno, Google Chrome and Obsidian**.

OCP configures an **existing, bootable Omarchy installation**. It does not install
the operating system, partition disks, or copy another machine's encryption keys.
This first release is experimental: its automated tests pass, but the included
Mac Pro profile has not been applied to a second computer. It is not yet a fleet
management server, a guarantee of compatibility, or a replacement for company
endpoint management.

## Quick start

Requires Python 3.10+, Bash and Git. Applying additionally uses Omarchy, pacman,
yay, sudo, and the destination's installed Limine tools. Run as your desktop user.

```bash
git clone <your-remote>/omarchy-computer-profiles.git
cd omarchy-computer-profiles
./ocp list
./ocp detect
./ocp show apple-macpro6-1
./ocp apply apple-macpro6-1                 # preview only
./ocp apply apple-macpro6-1 --execute       # apply after reviewing
```

Applying checks the vendor, model and CPU architecture. GPU/network PCI IDs
must also match; use `--allow-hardware-variant` only after reviewing differences.
Package managers retain their interactive confirmations. `--yes` is available
for reviewed automation. Profiles contain executable plugin code: only apply
profiles and upstream releases you trust. Checksums detect accidental changes;
they do not authenticate a profile author.

## Create and share a profile

Start on a machine where Omarchy already works well:

```bash
./ocp capture                             # automatic vendor/model ID
# Or identify a particular hardware variant:
./ocp capture --id apple-macpro6-1-d500 --description "Mac Pro 2013, D500 GPUs"
./ocp lock apple-macpro6-1-d500            # verify/pin brumm's release archive
./ocp validate apple-macpro6-1-d500
./ocp apply apple-macpro6-1-d500           # inspect the plan
```

Every capture prompts for an author name and requires a nonempty response. The
name is stored in `profile.json`, included in its README, and displayed by
`./ocp list`. Older profiles without author metadata display `Unknown`.

Capture reads local files and creates `profiles/<id>/`; it does not change the
computer's configuration or install software. An existing profile is never
overwritten: use a new variant ID or edit the original with a reviewed Git diff.
The lock step downloads metadata and the brumm archive, verifies its published
SHA-256 and stores the checksum. It never executes the downloaded release.

Review the profile's `README.md`, warnings, included files and software versions.
Test the profile on matching hardware and record the results. Then share through
normal Git workflows:

```bash
./ocp share apple-macpro6-1-d500            # stage only this profile
./ocp share apple-macpro6-1-d500 --commit
./ocp share apple-macpro6-1-d500 --commit --push
```

Push uses your existing remote, branch and credentials. For public contributions,
push to your fork and open a pull request. OCP never commits or uploads during
capture. Use `git pull --ff-only` to bring other contributors' profiles into your
clone. Files in `profiles/` are ordinary versioned repository files.

## What's captured

| Area | Contents |
| --- | --- |
| Hardware | DMI vendor/model/board, architecture, CPU model, PCI vendor/device/subsystem IDs and bound drivers |
| Environment | Omarchy, Hyprland and running kernel versions |
| Limine | Literal kernel options from installed Limine configuration and drop-ins, falling back to `/etc/kernel/cmdline` or `/proc/cmdline` |
| System configuration | Regular files in modprobe, modules-load, udev, Xorg and mkinitcpio drop-in directories; mbpfan and thermald settings when present |
| Drivers | Installed packages from a maintained hardware-package allowlist |
| Services | Enabled mbpfan and thermald services when present |
| Plugins | Installed user plugins except IDs in `disabledPlugins`; source revision/origin, local edits, code, images and native ELF helpers |
| Preferences | Monitor/input settings, Omarchy shell layout, Magic Trackpad settings, selected ZapFast appearance options and brumm display options |
| Software | Installation recipes for the six common applications; installed package versions recorded where available |

Built-in shell plugins remain supplied by Omarchy; the shell configuration records
which ones are disabled. When the shell isn't running, plugin detection uses the
saved configuration, not a live process query. Installed user service plugins can
be active without a bar item, so capture includes every user plugin not explicitly
disabled. Tracked files are used for Git plugins; untracked development files are
not included. Non-Git plugins are captured from their local files. Test fixtures,
Git metadata, caches and unsupported assets are excluded. Skipped assets are
listed per plugin. App-specific native runtimes installed outside plugin folders
may still need the upstream setup step; consult the captured README. OCP does
not execute arbitrary plugin installers automatically.

Plugin snapshots preserve local working copies and are tracked with their
profiles, including architecture-specific helpers. This favors fidelity over
repository size in v0.1. Large demo videos and files above 95 MiB are omitted.
Third-party licenses remain applicable; inspect them before public redistribution,
especially for local plugins without explicit licenses.

### Kernel options

OCP exports an allowlist of hardware-related option families, including AMD/Intel
GPU, PCIe, IOMMU, audio, USB, ACPI and other hardware quirks. Root, rootflags,
encryption, resume and disk identifiers are **never copied from the source**.
Unclassified options are recorded for review, not applied; extend the tested
allowlist to support another hardware option family.

Applying merges those options with the **destination's** existing Limine cmdline,
replacing conflicting hardware option keys while retaining destination boot
identity. An identifiable target `root=` is required. OCP appends a marked block
to `/etc/default/limine` and invokes `limine-update`; it does not copy `limine.conf`,
ESP paths, boot entries, EFI variables or the source's boot order. Existing target
options absent from the profile remain in place. Literal configuration is parsed
without sourcing shell scripts; dynamic assignments are rejected.

### Software

Arch repository packages are installed through pacman, with ZapFast falling back
to AUR via yay. Hardware AUR packages use their recorded provider. Pacman performs
a full system upgrade when installing packages; versions are recorded for context,
not frozen or downgraded. Bruno is installed per-user from Flathub, following
[Bruno's published installation method](https://www.usebruno.com/downloads) and
[Flatpak's CLI documentation](https://docs.flatpak.org/en/latest/using-flatpak.html).
Brumm uses a pinned [upstream release](https://github.com/chriopter/brumm/releases),
verified before extracting a fixed list of files. Its subscription/sign-in is
left to each user. The ZapFast package follows its [upstream Arch instructions](https://zapfast.rocks/download/).

## Apply selected sections

```bash
./ocp apply apple-macpro6-1 --sections hardware,boot
./ocp apply apple-macpro6-1 --sections software,plugins,preferences --execute
```

Sections are `hardware`, `boot`, `software`, `plugins`, `preferences`; all are
selected by default. `--execute` is always needed to mutate a computer. Resolve
any symlinked destination identified by OCP before applying; OCP refuses to follow
links while writing. Applying overlays files and does not delete unrelated target
configuration or plugins. A fresh Omarchy user gives the closest reproduction.
Fan limits and monitor scaling still need review on the target hardware.

## Backups and recovery

Before writing files, OCP creates a private journal under
`~/.local/state/ocp/backups/` and prints its location. Original file contents and
permissions are backed up before replacement, and newly added files are recorded.
Service enablement is also recorded. On error the installer stops and prints the
restore command; it does not claim an automatic rollback.

```bash
./ocp restore ~/.local/state/ocp/backups/<run>             # preview
./ocp restore ~/.local/state/ocp/backups/<run> --execute
```

Restore handles files and hardware services enabled by OCP. Package installations,
upgrades, Flatpak remotes and external app state are not rolled back. After
restoring hardware or boot files, run `sudo mkinitcpio -P` and `sudo limine-update`
before rebooting. Keep working installation/recovery media available when testing
boot changes. Log out/in for desktop changes; reboot for kernel/module changes.

## Privacy and contribution rules

Capture never reads browser profiles, mail databases, SSH keys, machine IDs,
serial numbers, disk layouts or brumm login tokens. ZapFast uses an explicit
preference allowlist, and credential/account/location keys are removed from JSON
settings. Recognizable private-key/token patterns abort export. These measures
are not a universal secret scanner: inspect every contribution, particularly
custom udev rules, comments and local plugin code.

For companies, maintain a private fork with reviewed profiles and a pilot group
for each model/GPU variant. Use Git review to promote configurations, record the
actual Omarchy/kernel version tested, and deploy through your existing management
system. `--yes` only removes package prompts; sudo authentication and other system
requirements still apply. Public profiles must not contain company-specific data.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the verification checklist and profile
format. No profile is automatically labelled verified merely because capture or
validation succeeded.

## Development

```bash
python3 -m unittest discover -s tests -v
./ocp validate apple-macpro6-1
```

The CLI uses only Python's standard library. Tests cover boot identity preservation,
unsafe/dynamic options, capture privacy, active plugin discovery, payload integrity,
hardware compatibility checks, symlink refusal and file restore. CI runs these
checks and validates every contributed profile. Real boot and hardware testing is
still needed on the target model.
