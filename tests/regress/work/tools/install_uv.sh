# @desc     with no python3 on PATH, a pip-based Mason package still installs: uv provides a managed Python (nothing written to uv's bin dir) and it goes first on nvim's PATH; with python3 present, uv installs nothing
# @areas    installer
# @budget   360
# @fixture  tools
. ./.tui.sh

# PATH without python3: /usr/bin becomes a symlink farm without python*, other dirs with python3 go
NOPY=$FIX/.nopy; mkdir -p "$NOPY"
for f in /usr/bin/*; do case ${f##*/} in python*) ;; *) ln -s "$f" "$NOPY/" ;; esac; done
nopath=
IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  if [ "$d" = /usr/bin ]; then nopath+=$NOPY:; elif [ ! -x "$d/python3" ]; then nopath+=$d:; fi
done
UVD=$FIX/.uv
uvenv=(UV_PYTHON_INSTALL_DIR=$UVD/python UV_CACHE_DIR=$UVD/cache UV_PYTHON_BIN_DIR=$UVD/bin)

# pip packages are the ones Mason installs into a venv
venvs() { find "$DATA/nvim/mason/packages" -mindepth 3 -maxdepth 3 -path '*/venv/bin/python' 2>/dev/null; }

start "PATH=${nopath%:}" "${uvenv[@]}" -- app.py
check "no python3: prompt for python" "wait_screen 'Install .* for python\?' 60"
mapfile -t py_pkgs < <(offered python)
answer Yes
check "no python3: Yes installs what the prompt offered" "[ ${#py_pkgs[@]} -gt 0 ] && all_installed 300 ${py_pkgs[*]}" "offered: ${py_pkgs[*]}"
if complete app.py 60; then pass "no python3: app.py completes, its servers attached and its tools on PATH"
else fail "no python3: app.py completes, its servers attached and its tools on PATH" "$(incomplete app.py)"; fi
if [ -n "$(venvs)" ]; then
  check "no python3: the uv Python is first on nvim's PATH" "q '.path_head' | grep -q '^$UVD/python/'"
  check "no python3: every pip package's venv uses the uv Python" "! venvs | xargs -r readlink -f | grep -qv '^$UVD/python/'" "$(venvs | xargs -r readlink -f | tr '\n' ' ')"
else info "python has no pip package to install: the uv path is not exercised"; fi
check "no python3: nothing written to uv's bin dir" "[ -z \"\$(ls -A $UVD/bin 2>/dev/null)\" ]"
stop

rm -rf "$UVD/python" "$DATA/nvim/mason"
start "${uvenv[@]}" -- app.py
check "python3 present: prompt" "wait_screen 'Install .* for python\?' 60"
mapfile -t py_pkgs < <(offered python)
answer Yes
check "python3 present: Yes installs what the prompt offered" "[ ${#py_pkgs[@]} -gt 0 ] && all_installed 300 ${py_pkgs[*]}" "offered: ${py_pkgs[*]}"
check "python3 present: uv installs no Python" "[ -z \"\$(ls -A $UVD/python 2>/dev/null)\" ]"
check "python3 present: PATH starts with Mason, not uv" "! q '.path_head' | grep -q '^$UVD/'"
stop
