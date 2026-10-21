#!/usr/bin/env bash
# 穿云 Windows smoke: run one smoke test, and once more if it fails (CI runners blip now and
# then). Between tries any leftover Chuanyun.exe is closed and the user proxy is switched off, so
# the second try starts clean. Every failed try leaves a public ::warning:: annotation.
#
#   bash tool/smoke/retry.sh <name> <tries> <command...>
name="$1"; tries="$2"; shift 2
for ((i = 1; i <= tries; i++)); do
  "$@" && { [ "$i" -gt 1 ] && echo "::warning title=$name::passed on try $i of $tries"; exit 0; }
  code=$?
  echo "::warning title=$name::try $i of $tries failed (exit $code)"
  if [ "$i" -lt "$tries" ]; then
    taskkill //F //IM Chuanyun.exe >/dev/null 2>&1 || true
    taskkill //F //IM ChuanyunGuard.exe >/dev/null 2>&1 || true
    taskkill //F //IM test_node.exe >/dev/null 2>&1 || true
    reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' //v ProxyEnable //t REG_DWORD //d 0 //f >/dev/null 2>&1 || true
    sleep 10
  fi
done
echo "::error title=$name::failed $tries times"
exit 1
