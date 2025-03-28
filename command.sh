#!/usr/bin/env bash

set -euo pipefail

# "catch exit status 1" grep wrapper
c1grep() {
  grep "$@" || test $? = 1
}

root_modules_dir="${ROOT_DIR_NAME}"
mapfile -d "${SEPARATOR}" -t changed_dirs < <(printf "%s" "${CHANGED_DIRS_RAW}")

# 1. Find all dirs that must be searched for root modules that might be affected by changes
search_root_module_dirs=()
for dir in "${changed_dirs[@]}"; do
  if [[ -d $dir ]]; then
    if [[ $dir =~ "/modules/" ]]; then
      # If dir name is in modules then we add dir containing modules to search path for root modules
      search_root_module_dirs+=("${dir//'/modules/'*}")
    elif [[ $dir =~ /${root_modules_dir}/ ]]; then
      search_root_module_dirs+=("${dir//"/${root_modules_dir}/"*}/${root_modules_dir}")
    else
      echo "::notice::$dir is neither in modules nor root modules paths, root search there is limited only to $dir itself"
      search_root_module_dirs+=("$dir")
    fi
  else
    echo "::warning::$dir is not a valid directory or it doesn't exist"
  fi
done

# 2. Find all root modules that might be affected by changes
root_module_dirs=()
for dir in "${search_root_module_dirs[@]}"; do
  echo "::debug::Searching $dir for root modules"
  new_root_module_dirs=$(c1grep -Plrz --exclude-dir=".terraform" 'terraform {(.|\n)*backend "' "$dir" | xargs -r dirname)
  root_module_dirs+=("${new_root_module_dirs[@]}")
done

mapfile -t unique_root_module_dirs < <(printf "%s\n" "${root_module_dirs[@]}" | sort -u | c1grep "\S")
echo "::debug::Unique root modules: ${unique_root_module_dirs[*]}"

# 3. Find all root modules that have any changes (including changes to dependencies)
get_deps() {
  local module_dir=$1
  c1grep -hE "^ *source *= *\"\.(\.)?/" "$module_dir/"*.{tf,tofu} | sed 's/.*"\(.*\)".*/\1/' | sort | uniq
}

has_changed_deps() {
  local module_dir=$1

  if [[ ${changed_dirs[*]} =~ $module_dir ]]; then
    return 0
  fi

  local raw_dep
  for raw_dep in $(get_deps "$module_dir"); do
    local dep_path
    dep_path=$(realpath --relative-to="$PWD" "$module_dir/$raw_dep")
    if has_changed_deps "$dep_path"; then
      return 0
    fi
  done

  return 1
}

changed_root_modules=()
for root_module_dir in "${unique_root_module_dirs[@]}"; do
  if has_changed_deps "$root_module_dir"; then
    changed_root_modules+=("$root_module_dir")
  fi
done

# 4. Output
echo "changed_root_modules=$(jq -cne '{"paths": [$ARGS.positional[]]}' --args "${changed_root_modules[@]}")" >> "${GITHUB_OUTPUT}"
echo "any_root_changed=${changed_root_modules[*]+"true"}" >> "${GITHUB_OUTPUT}"

mapfile -t changed_modules < <( printf '%s\n' "${changed_dirs[@]}" "${changed_root_modules[@]}" | sort -u | c1grep "\S")
echo "changed_modules=$(jq -cne '{"paths": [$ARGS.positional[]]}' --args "${changed_modules[@]}")" >> "${GITHUB_OUTPUT}"
echo "any_changed=${changed_modules[*]+"true"}" >> "${GITHUB_OUTPUT}"
