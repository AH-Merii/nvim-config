# @desc     answering Yes for go, yaml, c, terraform and php files leaves each buffer complete: what the prompt offered installed, every server Mason installed for its filetype attached and spawned from Mason, every formatter and linter whose command a Mason package provides installed and on PATH
# @areas    installer lsp format lint
# @budget   420
# @fixture  tools
. ./.tui.sh

files=(main.go config.yaml hello.c misfmt.tf index.php)
declare -A offers
start -- "${files[0]}"
wait=60 # the first prompt waits for the Mason registry download
for f in "${files[@]}"; do
  [ "$f" = "${files[0]}" ] || send "<Esc>:e $f<CR>"
  wait_q "[.bufs[] | select(.name == \"$f\" and .ft != \"\")] | length > 0" 20
  ft=$(q ".bufs[] | select(.name == \"$f\") | .ft")
  # a filetype may have nothing to install; what it lacks is caught below
  if wait_screen "Install .* for ${ft//./\\.}\?" "$wait"; then
    offers[$f]=$(offered "$ft" | tr '\n' ' ')
    answer Yes
  else info "$f ($ft): no install prompt"; fi
  wait=20
done

end=$((SECONDS + 240))
until [ "$(hq | jq -r .done)" = true ] || [ $SECONDS -ge $end ]; do sleep 1; done
J=$(hq)
check "state readable" "[ -n \"\$J\" ]" "no answer from nvim"
n=$(jq -r '.installing | length' <<<"$J")
[ "${n:-0}" -gt 0 ] && info "still installing: $(jq -r '[.installing[]] | join(",")' <<<"$J")"
for f in "${files[@]}"; do
  b=".bufs[] | select(.name == \"$f\")"
  info "$f ($(jq -r "$b | .ft" <<<"$J")): offered [${offers[$f]% }] attached [$(jq -r "[$b | .attached[]] | join(\",\")" <<<"$J")] expected [$(jq -r "[$b | .expected[]] | join(\",\")" <<<"$J")] tools [$(jq -r "[$b | .tools[] | .name + \"=\" + ([.packages[]] | join(\"|\"))] | join(\",\")" <<<"$J")]"
  # shellcheck disable=SC2086
  [ -n "${offers[$f]}" ] && check "$f: Yes installed everything the prompt offered" "all_installed 1 ${offers[$f]}" \
    "not installed: $(jq -r --arg o "${offers[$f]}" '($o | split(" ") | map(select(. != ""))) - .installed | join(",")' <<<"$J")"
  check "$f: every server Mason installed for its filetype attached" \
    "jq -e '$b | .missing | length == 0' <<<\"\$J\" >/dev/null" "missing: $(jq -r "[$b | .missing[]] | join(\",\")" <<<"$J")"
  check "$f: attached servers Mason installed run from Mason" \
    "jq -e '$b | .bad_bins | length == 0' <<<\"\$J\" >/dev/null" "$(jq -r "[$b | .bad_bins[]] | join(\" \")" <<<"$J")"
  check "$f: formatters and linters Mason provides are installed and on PATH" \
    "jq -e '$b | .tools_bad | length == 0' <<<\"\$J\" >/dev/null" "lacking: $(jq -r "[$b | .tools_bad[]] | join(\", \")" <<<"$J")"
done
stop
