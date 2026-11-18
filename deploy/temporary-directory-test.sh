#!/usr/bin/env bash

check_trusted_temporary_directory() (
  # shellcheck source=/dev/null
  . "$1"
  set +e
  local fixture_dir=$2/temporary-directory-checks directory status untrusted_parent
  local metadata_path metadata_owner=0 metadata_mode=755
  mkdir -p -- "$fixture_dir/parent/leaf" || exit
  fixture_dir=$(realpath -e -- "$fixture_dir") || exit
  untrusted_parent=$(mktemp -d /tmp/shipkeep-tmp-guard.XXXXXX) || exit
  trap 'rm -rf -- "$untrusted_parent"' EXIT
  mkdir -- "$untrusted_parent/leaf" || exit

  (unset TMPDIR; trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
  status=$?
  [[ $status == 0 ]] || die 'the default temporary directory was refused'
  grep -Fxq -- /tmp "$fixture_dir/output" || die 'the default temporary directory was not canonical'

  for directory in /tmp /usr; do
    (TMPDIR=$directory trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
    status=$?
    [[ $status == 0 ]] || die "a trusted root directory was refused: $directory"
    grep -Fxq -- "$directory" "$fixture_dir/output" || die 'a trusted temporary directory was not returned alone'
  done

  for directory in "$untrusted_parent" "$untrusted_parent/leaf"; do
    (TMPDIR=$directory trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
    status=$?
    [[ $status == 1 ]] || die 'a temporary directory owned by the test user was accepted'
    [[ ! -s $fixture_dir/output ]] || die 'an untrusted temporary directory was returned'
  done

  # shellcheck disable=SC2329
  stat() {
    local format=$2 path=${!#}
    case $format in
      %u)
        if [[ $path == "$metadata_path" ]]; then printf '%s\n' "$metadata_owner"; else printf '0\n'; fi
        ;;
      %a)
        if [[ $path == "$metadata_path" ]]; then printf '%s\n' "$metadata_mode"; else printf '755\n'; fi
        ;;
      *) return 1 ;;
    esac
  }

  metadata_path=$fixture_dir/parent/leaf
  metadata_mode=777
  (TMPDIR=$metadata_path trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
  status=$?
  [[ $status == 1 ]] || die 'a root-owned writable non-sticky temporary directory was accepted'

  metadata_mode=1777
  (TMPDIR=$metadata_path trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
  status=$?
  [[ $status == 0 ]] || die 'a root-owned sticky temporary directory was refused'
  grep -Fxq -- "$metadata_path" "$fixture_dir/output" || die 'the sticky temporary directory was not returned alone'

  metadata_path=$fixture_dir/parent
  metadata_mode=777
  (TMPDIR=$metadata_path/leaf trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
  status=$?
  [[ $status == 1 ]] || die 'a safe leaf below a writable non-sticky ancestor was accepted'

  metadata_mode=1777
  (TMPDIR=$metadata_path/leaf trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
  status=$?
  [[ $status == 0 ]] || die 'a safe leaf below a root-owned sticky ancestor was refused'

  metadata_mode=755
  metadata_owner=1000
  (TMPDIR=$metadata_path/leaf trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
  status=$?
  [[ $status == 1 ]] || die 'a root-owned leaf below an untrusted ancestor was accepted'

  metadata_mode=1777
  (TMPDIR=$metadata_path/leaf trusted_temporary_directory) >"$fixture_dir/output" 2>"$fixture_dir/error"
  status=$?
  [[ $status == 1 ]] || die 'a root-owned leaf below an untrusted sticky ancestor was accepted'
)
