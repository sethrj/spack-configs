#!/bin/bash -e
###############################################################################
# File : update-local.sh
###############################################################################

# In case the user executed directly with `sh`
set -e

function cecho()
{
  local color=$1
  shift
  local text=$1
  shift
  printf "\e[${color}m${text//%/%%}\e[0m\n" >&2
}
function info() { cecho 32 "-- $@"; };
function status() { cecho "34;1" "-- $@"; };
function error() { cecho "31;1" "ERROR: $@"; exit 1; };

# Verbose call: echo before running
function vcall() { cecho "37;2" "> $*"; "$@"; }

if [ "$0" != "$BASH_SOURCE" ]; then
  cecho "31;1" "ERROR: Run this script directly, do not \`source\` it"
  return 1
fi

###############################################################################

if [ -z "${SPACK_ROOT}" ]; then
  error "Spack not loaded: ${SPACK_ROOT} must be defined"
fi
if ! hash spack 2>/dev/null; then
  source ${SPACK_ROOT}/share/spack/setup-env.sh
fi
SPACK_ENV_BASE="$SPACK_ROOT/var/spack/environments"

if [ -n "${LMOD_SYSTEM_NAME}" ]; then
  # OLCF systems
  SHORTHOST=${LMOD_SYSTEM_NAME}
elif [ -n "${PBS_O_HOST}" ]; then
  # On compute node
  SHORTHOST=${PBS_O_HOST}
else
  SHORTHOST=$(uname -n)
fi
SHORTHOST=${SHORTHOST%%.*}
CONFIGDIR="$( cd "$( dirname "$0" )" && pwd )"/$SHORTHOST
if [ ! -d $CONFIGDIR ]; then
  mkdir $CONFIGDIR
fi
cd $CONFIGDIR
if [ ! -d env ]; then
  mkdir env
fi

status "Backing up config and environments to ${CONFIGDIR}"
vcall cp "${SPACK_ROOT}/etc/spack/site/"*.yaml "./" \
    || vcall cp "${SPACK_ROOT}/etc/spack/"*.yaml "./" \
    || printf "\e[31;1m(no site spack configs are present)\e[0m "
spack debug report > spack-debug-report.md
for env in $(cd ${SPACK_ENV_BASE} && ls); do
  printf "$env " >&2
  cp "${SPACK_ENV_BASE}/${env}/spack.yaml" "env/${env}.yaml" \
    || printf "\e[31;1m(missing environment)\e[0m "
  cp "${SPACK_ENV_BASE}/${env}/spack.lock" "env/${env}.lock" 2>/dev/null \
    || printf "\e[31;1m(missing lock)\e[0m "
done
cecho 32 "...done"

if command -v brew > /dev/null 2>&1; then
  status "Saving homebrew"
  brew bundle dump --describe -f
fi

if command -v conda > /dev/null 2>&1; then
  status "Saving conda environments"
  for env in $(conda env list | awk '{print $1}' | tail -n +4); do
    status "Saving conda environment: $env"
    conda list -n "$env" --export > "conda-${env}-packages.txt" \
      || printf "\e[31;1m(failed to save conda environment: $env)\e[0m "
  done
fi

if ! git config user.name >/dev/null; then
  error "Please execute 'git config --global user "Name <email>"'"
fi

git add .
if [ -n "$(git diff --name-only --cached -- .)" ]; then
  git pull --ff-only
  vcall git commit -m "Update $SHORTHOST" -- .
  git push
else
  info "No changes to committed environment files"
fi
