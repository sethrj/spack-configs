# ExCL Spack setup

The shared network space `PROJ=/auto/projects/celeritas` has:
- `$PROJ/spack`: the main Spack clone, which is mostly immutable *except* for
  the default source caches (`var/spack/cache/`).
- `$PROJ/buildcache`: relocatable binaries cached by spack after building
- `$PROJ/environments`: environment configurations and metadata (not
  installations!) for each system

## Each environment

An environment in Spack is usually a directory with a `spack.yaml` file.
I have one environment per machine, currently called `celer-{system}`, which
contains three aliases and one main environment file:

- `celeritas-packages.yaml -> ../celeritas-packages.yaml*`:
  [requirements from Celeritas](https://github.com/celeritas-project/celeritas/blob/develop/scripts/spack/packages.yaml)
- `excl.yaml -> ../excl.yaml`: common excl setup (buildcache, etc.)
- `milan2.yaml -> ../milan2.yaml`: system-specific setup (externals)
- `spack.yaml`: includes the three files above and defines environment
  requirements

The Spack environment for milan2 merges the ExCL requirements, the Celeritas
package constraints+preferences, the system-specific externals, and the list of package requirements:

```yaml
spack:
  include:
    - excl.yaml
    - celeritas-packages.yaml
    - milan2.yaml
    
  specs:
    - ccache
    - py-pre-commit
    - cmake
    - ninja
    - git-lfs
    - git
    - libtree
    - python
    - cuda@12.9

    - cli11
    - nlohmann-json
    - geant4
    - googletest
    - covfie +cuda cuda_arch=70
    - g4vg
    - hepmc3
    - vecgeom +cuda cuda_arch=70
    - root
```

I have found the easiest way to specify CUDA requirements (`cuda_arch` is
targeted to a specific GPU) is in these specs rather than in a `{system}.yaml`
file.

To get system-specific requirements, I'll activate the environment and run
`spack find {whatever}`, then move the packages from the main `spack.yaml` to
the `{system}.yaml`. To get the already-installed ROCm libraries for Faraday, I
used `spack external find --tag rocm`. Some system packages have slightly
different versions across machines, which can limit buildcache reuse, so choose
carefully what to use from the system. (I avoid using the system python.)

## Cross-machine build setup

The `excl.yaml` file is used for options that need to be same across
installations to maximize build reuse.
- The config install tree should generally have a "padded length" to allow it
  to be relocated to other install directories in the future. Without it,
  binaries could not be installed at `/scratch/celeritas-new/opt`.
- The `config.install_tree.root` should be in `/scratch` to avoid NFS overhead.
- The `mirrors` section defines a local binary mirror named `projects`:
  binaries are copied to and from this directory.
- The `view` for the environment needs to be in `/scratch` rather than the
  network drive.
- Concretization settings need to create a unified view.
- A "generic" architecture (the greatest common denominator of all CPU features
  on ExCL systems being used) needs to be selected for all packages:
  `x86_64_v3` is a common choice.
- Other package preferences, such as default variants for disabling X11 or
  using cmake/ninja, can also be added to the packages.

```yaml
config:
  concurrent_packages: 8
  locks: false
  build_jobs: 48
  install_tree:
    padded_length: 128
    root: /scratch/celeritas/opt
    projections:
      all: "{name}/{version}/{hash:7}"

mirrors:
  projects:
    url: /auto/projects/celeritas/buildcache
    binary: true
    signed: false
    autopush: false

view:
  default:
    root: /scratch/celeritas/view

concretizer:
  unify: true
  targets:
    granularity: generic
    host_compatible: true

packages:
  all:
    target: [x86_64_v3]
    require:
      - target=x86_64_v3
```

## Installing the environment

Once you have spack installed, create your environment directory and the
symlinks inside it. Then run:
```console
$ spack env activate .
$ spack concretize -f --fresh --non-defaults
$ spack install
$ spack buildcache push projects
```

The first environment will probably build everything from scratch. The
`buildcache push` will print a warning the first time, but then (from within
the environment) `spack buildcache list --allarch` should show that most of the
specs have been "uploaded" (copied) to the cache directory.

Subsequent environment concretization *should* (if using the very latest spack,
maybe 1.3?) print `[b]` markers next to most of the packages that can be
reused. (Generally speaking, this is everything but CUDA packages.) Then the
`spack install` step will be extremely fast, since installation will be a
decompression with a binary relocation mechanism.
