#!/usr/bin/env bash

check_docker_repository() (
  set +e
  local installer=$1 apt_dir=$2 status
  local sources=$apt_dir/sources.list.d/shipkeep-docker.sources keyring=$apt_dir/keyrings/shipkeep-docker.gpg
  mkdir -p -- "$apt_dir/sources.list.d" "$apt_dir/keyrings" || exit

  run_docker_install "$installer" "$apt_dir" fail-download >"$apt_dir/output" 2>&1
  status=$?
  [[ $status == 100 ]] || die "Docker download failure returned $status"
  grep -q 'Simulated Docker download failure' "$apt_dir/output" || die 'Docker download was not reached'
  [[ ! -e $sources && ! -e $keyring ]] || die 'a failed download left repository files behind'

  run_docker_install "$installer" "$apt_dir" fail-update >"$apt_dir/output" 2>&1
  status=$?
  [[ $status == 100 ]] || die "Docker repository update failure returned $status"
  grep -q 'Simulated Docker repository update failure' "$apt_dir/output" || die 'Docker repository update was not reached'
  [[ ! -e $sources && ! -e $keyring ]] || die 'a failed repository update left repository files behind'

  run_docker_install "$installer" "$apt_dir" appear-during-setup >"$apt_dir/output" 2>&1
  status=$?
  [[ $status == 1 && ! -e $keyring ]] || die 'a conflict during setup did not roll back the new keyring'
  grep -Fxq -- 'late repository' "$sources" || die 'a repository added during setup was modified'
  rm -- "$sources"

  run_docker_install "$installer" "$apt_dir" appear-fifo >"$apt_dir/output" 2>&1
  status=$?
  [[ $status == 1 && -p $sources && ! -e $keyring ]] || die 'a FIFO added during setup was not refused and preserved'
  rm -- "$sources"

  run_docker_install "$installer" "$apt_dir" success >"$apt_dir/output" 2>&1 || die 'a retry after a failed download was refused'
  grep -Fxq -- "Signed-By: $keyring" "$sources" || die 'a successful installation did not keep its signed repository'
  grep -Fxq -- 'test Docker keyring' "$keyring" || die 'a successful installation did not keep its signing key'

  printf 'foreign repository\n' >"$sources"
  printf 'foreign keyring\n' >"$keyring"
  run_docker_install "$installer" "$apt_dir" success >"$apt_dir/output" 2>&1
  status=$?
  [[ $status == 1 ]] || die "an existing repository returned $status"
  grep -q 'Docker repository file already exists' "$apt_dir/output" || die 'existing repository was refused without saying why'
  grep -Fxq -- 'foreign repository' "$sources" || die 'an existing repository file was modified'
  grep -Fxq -- 'foreign keyring' "$keyring" || die 'an existing keyring was modified'

  rm -- "$sources" "$keyring"
  ln -s -- "$apt_dir/missing" "$keyring"
  run_docker_install "$installer" "$apt_dir" success >"$apt_dir/output" 2>&1
  status=$?
  [[ $status == 1 && -L $keyring && ! -e $apt_dir/missing ]] || die 'a dangling keyring link was not preserved'
  [[ -z $(find "$apt_dir" -name '.shipkeep-docker.*' -print -quit) ]] || die 'a repository draft was left behind'
)

run_docker_install() {
  timeout 10s bash -s -- "$@" <<'BASH'
. "$1"

sources=$2/sources.list.d/shipkeep-docker.sources

curl() { :; }
single_signing_key() {
  [[ $3 == 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 ]] || return 1
  printf 'test Docker keyring\n' >"$2"
  if [[ $failure == appear-during-setup ]]; then
    printf 'late repository\n' >"$sources"
  elif [[ $failure == appear-fifo ]]; then
    mkfifo "$sources"
  fi
}
apt-get() {
  if [[ $1 == update && $failure == fail-update && -f $sources ]]; then
    printf 'Simulated Docker repository update failure\n' >&2
    return 100
  fi
  if [[ " $* " == *' docker-ce '* && $failure == fail-download ]]; then
    printf 'Simulated Docker download failure\n' >&2
    return 100
  fi
}

failure=$3
install_docker_packages "$2"
BASH
}
