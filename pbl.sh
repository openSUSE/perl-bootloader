#! /usr/bin/sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# This is a (wrapper) script to update the bootloader config.
#
# It checks /etc/sysconfig/bootloader for the bootloader type.
#
# If there's no bootloader configured, it does nothing.
#
# If the directory /usr/lib/bootloader/$LOADER exists, runs the scripts from
# that directory.
#

VERSION="0.0"

bl_dir="/usr/lib/bootloader"
sysconfig_dir="/etc/sysconfig"
logfile="/var/log/pbl.log"

program="${0##*/}"
program="${program%.sh}"
pid="$$"

PATH="/usr/bin:/usr/sbin:/bin:/sbin"


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# bl_usage EXIT_CODE
#
# Print help text and exit with EXIT_CODE.
#
bl_usage ()
{
  out=2
  [ "$1" = 0 ] && out=1

  cat <<=== >&$out
Usage: pbl [OPTIONS]
Configure/install boot loader.

Options:
    --install                   Install boot loader.
    --config                    Create boot loader config.
    --show                      Print current boot loader.
    --loader BOOTLOADER         Set current boot loader to BOOTLOADER.
                                Supported values: none, grub2, grub2-bls, grub2-efi, systemd-boot, u-boot.
    --default ENTRY             Set default boot entry to ENTRY.
    --add-option OPTION         Add OPTION to default boot options (grub2).
    --del-option OPTION         Delete OPTION from default boot options (grub2).
    --get-option OPTION         Get OPTION from default boot options (grub2).
    --add-kernel VERSION [KERNEL [INITRD]]
                                Add kernel with version VERSION. Optionally pass kernel and initrd
                                explicitly (systemd-boot).
    --remove-kernel VERSION     Remove kernel with version VERSION (systemd-boot).
    --default-settings          Return default kernel, initrd, and boot options.
    --log LOGFILE               Log messages to LOGFILE (default: /var/log/pbl.log)
    --version                   Show pbl version.
    --help                      Write this help text.

===

  exit "$1"
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# bootloader_entry_usage EXIT_CODE
#
# Print help text and exit with EXIT_CODE.
#
bootloader_entry_usage ()
{
  out=2
  [ "$1" = 0 ] && out=1

  cat <<=== >&$out
Usage: bootloader_entry add|remove kernel-flavor kernel-version kernel-image initrd-file
Add or remove kernel images to boot config.
===

  exit "$1"
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# log_msg LEVEL MESSAGE EXTRA_CONTENT
#
#   LEVEL: 1 .. 3
#   MESSAGE: string (single line)
#   EXTRA_CONTENT: multi-line string (e.g. some program output)
#
# Log message to log file.
#
log_msg ()
{
  msg=$(date "+%F %T")
  msg="$msg <$1> $program-$pid: $2"

  echo "$msg" >>"$logfile"
  if [ "$3" != "" ] ; then
    f=$(echo "$3" | sed -e 's/\n+$//')
    { echo ">>>>>>>>>>>>>>>>" ; echo "$f" ; echo "<<<<<<<<<<<<<<<<" ; } >>"$logfile"
  fi
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# read_config FILE PREFIX
#
# Read config settings from FILE and convert them into environment vars of
# the form:
#
# PREFIX__KEY=value
#
# Note that this parser assumes config files to stick to a KEY="VALUE" syntax.
#
read_config ()
{
  [ -r "$1" ] || return

  old_ifs="$IFS"
  IFS="="
  while read -r key value ; do
    if [ -n "$key" -a "$key" = "${key###}" ] ; then
      sys_key="$2__$key"
      eval "$sys_key=\$(lib_shellquote $value)"
      export "${sys_key?}"
    fi
  done < "$1"
  IFS="$old_ifs"
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# read_sysconfig FILE
#
# Read sysconfig settings from /etc/sysconfig/FILE and convert them into
# environment vars of the form:
#
# SYS__FILENAME__KEY=value
#
read_sysconfig ()
{
  filename=$(echo "$1" | tr "[:lower:]" "[:upper:]")

  read_config "$sysconfig_dir/$1" "SYS__${filename}"
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# exit_code = run_command ARGS
#
# Run external command with arguments ARGS. All output is logged.
#
# The external command may put anything into the (temporary) file passed via
# the 'PBL_RESULT' environment variable. The content of that file is read and
# printed to STDOUT.
#
run_command ()
{
  PBL_RESULT=$(mktemp)
  export PBL_RESULT

  command="${*}"

  output=$("${@}" 2>&1)

  err=$?

  if [ "$err" = 0 ]  ; then
    log_msg 1 "'$command' = $err, output:" "$output"
    if [ -s "$PBL_RESULT" ] ; then
      result=$(cat "$PBL_RESULT")
    fi
    if [ -n "$result" ] ; then
      log_msg 1 "result:" "$result"
      echo "$result"
    fi
  else
    log_msg 3 "'$command' failed with exit code $err, output:" "$output"
    echo "$output" 2>&1
  fi

  rm -f "$PBL_RESULT"
  unset PBL_RESULT

  return "$err"
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# exit_code = run_script script ARGS
#
# Run script from /usr/lib/bootloader/$loader with arguments ARGS.
# All output is logged.
#
run_script ()
{
  opt="$1"
  cmd="$bl_dir/$loader/$1"
  shift

  if [ -x "$cmd" ] ; then
    run_command "$cmd" "$@"
    err=$?
  else
    log_msg 1 "$cmd skipped"
    if [ "$program" = pbl ] ; then
      echo "Option --$opt not available for $loader."
    fi
    err=0
  fi

  return "$err"
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# set_log LOG_FILE
#
# Log to LOG_FILE or STDERR if LOG_FILE is not writable.
#
set_log ()
{
  logfile="$1"

  if [ ! -e "$logfile" ] ; then
    eval "echo -n >'$logfile'" 2>/dev/null
  fi

  if [ ! -w "$logfile" ] ; then
    logfile="/dev/fd/2"
  fi
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# set_loader LOADER
#
# Set LOADER_TYPE in $sysconfig_dir/bootloader to LOADER.
#
set_loader ()
{
  if [ "$1" = grub2-bls -a "$DEFAULT__GRUB_ENABLE_BLSCFG" = false ] ; then
    lib_set_config "/etc/default/grub" "GRUB_ENABLE_BLSCFG" "true"
  elif [ \( "$1" = grub2-efi -o "$1" = grub2 \) -a "$DEFAULT__GRUB_ENABLE_BLSCFG" = true ] ; then
    lib_set_config "/etc/default/grub" "GRUB_ENABLE_BLSCFG" "false"
  fi

  lib_set_config "$sysconfig_dir/bootloader" "LOADER_TYPE" "$1"

  return $?
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# check_args N ARGS
#
# Check that argument list ARGS starts with an option and is followed
# by N non-option values.
#
check_args ()
{
  n="$1"
  shift

  n_orig="$n"

  opt="$1"
  shift

  # option arguments are not empty and don't start with '-'
  while [ "$n" -gt 0 ] ; do
    if [ -z "$1" -o "$1" != "${1#-}" ] ; then
      if [ "$n_orig" = 1 ] ; then
        echo "option $opt requires $n_orig argument" >&2
      else
        echo "option $opt requires $n_orig arguments" >&2
      fi
      bl_usage 1
    fi

    shift
    n="$((n-1))"
  done
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

PBL_INCLUDE="$bl_dir/include"
export PBL_INCLUDE

# include common functions
. "$PBL_INCLUDE/library"

# get relevant settings
read_sysconfig "bootloader";
read_sysconfig "language";

read_config "/etc/default/grub" "DEFAULT"

loader="$SYS__BOOTLOADER__LOADER_TYPE"
lang="$SYS__LANGUAGE__RC_LANG"

if [ "$loader" = grub2-efi -a "$DEFAULT__GRUB_ENABLE_BLSCFG" = true ] ; then
  loader=grub2-bls
elif [ "$loader" = grub2-bls -a "$DEFAULT__GRUB_ENABLE_BLSCFG" = false ] ; then
  loader=grub2-efi
fi

set_log "$logfile"

log_msg 1 "bootloader = $loader"

if [ -n "$lang" ] ; then
  log_msg 1 "locale = $lang"
  unset LC_MESSAGES
  unset LC_ALL
  LANG="$lang"
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# compat: called as bootloader_entry
#
if [ "$program" = bootloader_entry ] ; then
  # notes
  #   - there might be an optional 6th argument 'force-default' - ignore it
  #   - the kernel-flavor arg is also ignored
  #
  if [ "$#" -ge 5 ] ; then
    case "$1" in
      add|remove) run_script "$1-kernel" "$3" "$4" "$5" && run_script "config" ; exit ;;
    esac
  fi

  bootloader_entry_usage 1
fi


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# compat: called as update-bootloader
#
if [ "$program" = update-bootloader ] ; then
  while true ; do
    case $1 in
      --reinit) shift ; run_script "install" && run_script "config" ; exit ;;
      ?*) shift ; continue ;;
    esac

    break
  done

  run_script "config"

  exit
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# called as pbl
#

while true ; do
  [ -z "$1" ] && break

  case $1 in
    --show ) echo "$loader" ; exit 0 ;;
    --loader ) check_args 1 "${@}" ; shift ; set_loader "$1" || exit ; shift ; continue ;;
    --log) check_args 1 "${@}" ; shift ; set_log "$1" ; shift ; continue ;;
    --version) echo "$VERSION" ; exit 0 ;;
    --help) bl_usage 0 ;;
  esac

  if [ "$loader" = "" -o "$loader" = none ] ; then
    exit 0
  fi

  if [ ! -d "/usr/lib/bootloader/$loader" -o "$loader" = include ] ; then
    echo "bootloader \"$loader\" not supported" >&2
    exit 1
  fi

  case $1 in
    --install) shift ; run_script "install" || exit ; continue ;;
    --config) shift ; run_script "config" || exit ; continue ;;
    --default ) check_args 1 "${@}" ; shift ; run_script "default" "$1" || exit ; shift ; continue ;;
    --add-option ) check_args 1 "${@}" ; shift ; run_script "add-option" "$1" || exit ; shift ; continue ;;
    --del-option ) check_args 1 "${@}" ; shift ; run_script "del-option" "$1" || exit ; shift ; continue ;;
    --get-option ) check_args 1 "${@}" ; shift ; run_script "get-option" "$1" || exit ; shift ; continue ;;
    --default-settings) shift ; run_script "default-settings" || exit ; continue ;;
    --add-kernel ) check_args 1 "${@}" ; shift
      v="$1" ; shift
      k=
      i=
      [ -n "$1" -a "$1" = "${1#-}" ] && { k="$1" ; shift ; }
      [ -n "$1" -a "$1" = "${1#-}" ] && { i="$1" ; shift ; }
      run_script "add-kernel" "$v" "$k" "$i" || exit
      continue ;;
    --remove-kernel ) check_args 1 "${@}" ; shift
      v="$1" ; shift
      run_script "remove-kernel" "$v" || exit
      continue ;;
    -*) echo "unknown option: $1" >&2 ; bl_usage 1 ;;
  esac

  break
done

[ -n "$1" ] && bl_usage 1

exit 0
