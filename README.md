# changed-tf-modules
Contains Github action that given a list of changed files gets a list of changed terraform modules

Given the input of a list of directories this action is used to get
- changed terraform modules (root or shared)
- changed terraform root modules

## Implementation details
### changed_dirs input
Normally it's expected to get this input from `tj-actions/changed-files` (or similar aciton) by setting to true `get_changed_dirs` or `dir_names` flag respectively.
But also, this list can be constructed in other way as long as it respects the same output structure: it's a single string of paths that are split by `separator`.

### Folder structure assumptions
For `command.sh` script to properly work and account for all modules there are several assumptions that are made that all must be true:
1. All shared local modules are under `modules/` folders
2. If module `M` depends on sharable module `S` and the module `S` is on `prefix_path/modules/S` the module `M` must be located inside `prefix_path/` somewhere (can be multiple levels deeper)
3. All root modules are located under folders with the same name specified by `${root_module_dir_name}` input
For any changes made outside of that structure root modules are only searched for in the same directory where changes are made.

### Root module detection
To check that the module is a root module the script does not search for `.terraform.lock.hcl` files but instead looks for
```hcl
terraform {
  backend "
```
part on the path including sub-folders.

This is because existence of the lock file is not guaranteed but established practice is to always specify terraform backend configuration explicitly in the code where the rest of the module is defined.

NOTE: if this practice changes in the future the detection method should be revisited.

### Dependency changes detection algorithm
The process to detect if any of the root module dependencies changed is by going over two steps
1. Check if the current path is matching any of changed directories and stop if the change is detected
2. Follow reference paths in `source` to local modules (these references must be starting like `./` or `../`) and for each path recurse to `1`.
3. If no matches with changed directories are encountered then nothing has changed that algorithm is accounting for

### Known limitations
- algorithm is not accounting for changes in non terraform files (e.g. scripts), this can be implemented if necessary
- algorithm isn't optimized, actually the reverse search is faster but given the execution time of a few seconds in medium-sized repository there's no reason to rework this potentially ever
