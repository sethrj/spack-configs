#!/bin/bash -e
###############################################################################
# File  :  ci/admin/install-spack.sh
###############################################################################

if [ "$0" != "$BASH_SOURCE" ]; then
  cecho "31;1" "ERROR: Run this script directly, do not \`source\` it"
  return 1
fi

if [ "$USER" == "root" ]; then
  cecho "31;1" "ERROR: Run this script in user mode, do not \`sudo\` it"
  exit 1
fi

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

###############################################################################

if [ -z "${SPACK_ROOT}" ]; then
  error "Spack not loaded: ${SPACK_ROOT} must be defined"
fi
if ! hash spack 2>/dev/null; then
  source ${SPACK_ROOT}/share/spack/setup-env.sh
fi
SPACK_ENV_BASE="$SPACK_ROOT/var/spack/environments"

SHORTHOST=${PBS_O_HOST:-$HOSTNAME}
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
vcall cp "${SPACK_ROOT}/etc/spack/"*.yaml "./"
spack debug report > spack-debug-report.md
for env in $(cd ${SPACK_ENV_BASE} && ls); do
  printf "$env " >&2
  cp "${SPACK_ENV_BASE}/${env}/spack.yaml" "env/${env}.yaml"
  cp "${SPACK_ENV_BASE}/${env}/spack.lock" "env/${env}.lock" 2>/dev/null \
    || printf "\e[31;1m(missing lock)\e[0m "
done
cecho 32 "...done"

if ! git config user.name >/dev/null; then
  info "Setting default git user name to $USER"
  git config --global user.name "$USER"
fi
if ! git config user.email >/dev/null; then
  _email=scalehelp@ornl.gov
  info "Setting default git user email to ${_email}"
  git config --global user.email "${_email}"
fi


git add .
if [ -n "$(git diff --name-only --cached -- .)" ]; then
  git pull --ff-only
  vcall git commit -m "Update $SHORTHOST" -- .
  git push
else
  info "No changes to committed environment files"
fi
