# Third-party material

Code written in this repo (`kexts/`, `scripts/`, `test/`, `tools/`) is under the [Clear BSD License](LICENSE) unless the table
says otherwise.

| Item | Where | Origin | License |
|---|---|---|---|
| NullMoth patch | `patches/nmx/0001-accel-task-private-va.patch` | A patch against the sources of NullMoth's NVIDIA/AMD macOS driver (<https://github.com/nullmoth/nvidia-macos-driver>) | That project is under the **PolyForm Noncommercial License 1.0.0**. Treat the patch as derived work with those terms (noncommercial use, license notice passed on), not as Clear BSD |
| Docs that quote NullMoth behaviour | `docs/NULLMOTH*.md`, `docs/890M-*.md` | Observations of the NullMoth binaries on the reference machine | Observations and short excerpts of symbol names only; the binaries are not included |
| macOS IOAccelerator profile | `abi/strix/24H32/ioaccel-profile.json` | Symbol names and layout facts read from Apple's IOAccelerator kexts on macOS 24H32 | Facts about an interface; no Apple code or binary is included |

Apple's binaries, the NullMoth driver, NVIDIA's firmware and the AMD VBIOS are **not included** in this repository; `ref/`
and `tools/bin/` are git-ignored on purpose. Scripts that need them say where to get them.

## Reference material (read, not copied)

The research read the following; no code from them is included here. Check each project for its own license before reusing
anything.

* Linux `amdgpu` / `drm` (GPL-2.0) for the DCN35, SMU, PSP and GFX bring-up order that the traces compare against.
* [ChefKissInc/NootedRed](https://github.com/ChefKissInc/NootedRed) and similar AMD iGPU projects for macOS, as architecture
  references.
* [acidanthera/Lilu](https://github.com/acidanthera/Lilu) (headers cloned at build time for StrixHeadroom, not redistributed)
  and [acidanthera/MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) (build time only).
