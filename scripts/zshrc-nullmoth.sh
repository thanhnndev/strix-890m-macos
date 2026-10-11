# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Source from ~/.zshrc (or ~/.bashrc):  source ~/develop/projects/ga403wm-hackintosh/scripts/zshrc-nullmoth.sh
# NullMoth's Metal plugin exports MESA_SHADER_CACHE_DIR; a shell can inherit one that points at another user's cache
# directory (seen: root's). Mesa then disables its shader disk cache for every Metal program started from the shell.
# Drop the variable when it is not writable, so Mesa falls back to ~/.cache/mesa_shader_cache.
if [ -n "${MESA_SHADER_CACHE_DIR:-}" ] && [ ! -w "$MESA_SHADER_CACHE_DIR" ]; then
  unset MESA_SHADER_CACHE_DIR
fi
