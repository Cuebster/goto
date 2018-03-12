#!/usr/bin/env bash
# MIT License
#
# Copyright (c) 2018 Lazarus Lazaridis
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Changes to the given alias directory
# or executes a command based on the arguments.
function goto()
{
  local target
  GOTO_DB="$HOME/.goto"

  if [ -z "$1" ]; then
    # display usage and exit when no args
    _goto_usage
    return
  fi

  subcommand="$1"
  shift
  case "$subcommand" in
    -c|--cleanup)
      _goto_cleanup "$@"
      ;;
    -r|--register) # Register an alias
      _goto_register_alias "$@"
      ;;
    -u|--unregister) # Unregister an alias
      _goto_unregister_alias "$@"
      ;;
    -l|--list)
      _goto_list_aliases
      ;;
    -h|--help)
      _goto_usage
      ;;
    -v|--version)
      _goto_version
      ;;
    *)
      _goto_directory "$subcommand"
      ;;
  esac
}

function _goto_usage()
{
  cat <<\USAGE
usage: goto [<option>] <alias> [<directory>]

default usage:
  goto <alias> - changes to the directory registered for the given alias

OPTIONS:
  -r, --register: registers an alias
    goto -r|--register <alias> <directory>
  -u, --unregister: unregisters an alias
    goto -u|--unregister <alias>
  -l, --list: lists aliases
    goto -l|--list
  -c, --cleanup: cleans up non existent directory aliases
    goto -c|--cleanup
  -h, --help: prints this help
    goto -h|--help
  -v, --version: displays the version of the goto script
    goto -v|--version
USAGE
}

# Displays version
function _goto_version()
{
  echo "goto version 1.0.0"
}

# Expands directory.
# Helpful for ~, ., .. paths
function _goto_expand_directory()
{
  cd "$1" 2>/dev/null && pwd
}

# Lists registered aliases.
function _goto_list_aliases()
{
  local IFS=$'\n'
  if [ -f "$GOTO_DB" ]; then
    sed '/^\s*$/d' "$GOTO_DB" 2>/dev/null
  else
    echo "You haven't configured any directory aliases yet."
  fi
}

function _goto_find_duplicate()
{
  local duplicates=

  duplicates=$(sed -n 's:[^ ]* '"$1"'$:&:p' "$GOTO_DB" 2>/dev/null)
  echo "$duplicates"
}

# Registers and alias.
function _goto_register_alias()
{
  if [ "$#" -ne "2" ]; then
    _goto_error "usage: goto -r|--register <alias> <directory>"
    return
  fi

  if ! [[ $1 =~ ^[[:alnum:]]+[a-zA-Z0-9_-]*$ ]]; then
    _goto_error "invalid alias - can start with letters or digits followed by letters, digits, hyphens or underscores"
    return
  fi

  local resolved
  resolved=$(_goto_find_alias_directory "$1")

  if [ -n "$resolved" ]; then
    _goto_error "alias '$1' exists"
    return
  fi

  local directory
  directory=$(_goto_expand_directory "$2")
  if [ -z "$directory" ]; then
    _goto_error "failed to register '$1' to '$2' - can't cd to directory"
    return
  fi

  local duplicate
  duplicate=$(_goto_find_duplicate "$directory")

  # Append entry to file.
  echo "$1 $directory" >> "$GOTO_DB"
  echo "Alias '$1' registered successfully."
  
  if [ -n "$duplicate" ]; then
    echo -e "note: duplicate alias found:\n$duplicate"
    return
  fi
}

# Unregisters the given alias.
function _goto_unregister_alias
{
  if [ "$#" -ne "1" ]; then
    _goto_error "usage: goto -u|--unregister <alias>"
    return
  fi

  local resolved
  resolved=$(_goto_find_alias_directory "$1")
  if [ -z "$resolved" ]; then
    _goto_error "alias '$1' does not exist"
    return
  fi

  # shellcheck disable=SC2034
  local readonly GOTO_DB_TMP="$HOME/.goto_"
  # Delete entry from file.
  sed "/^$1 /d" "$GOTO_DB" > "$GOTO_DB_TMP" && mv "$GOTO_DB_TMP" "$GOTO_DB"
  echo "Alias '$1' unregistered successfully."
}

# Unregisters aliases whose directories no longer exist.
function _goto_cleanup()
{
  if ! [ -f "$GOTO_DB" ]; then
    return
  fi

  local IFS=$'\n' match matches al dir

  read -d '' -r -a matches < "$GOTO_DB"

  IFS=' '
  for i in "${!matches[@]}"; do
    read -r -a match <<< "${matches[$i]}"

    al="${match[0]}"
    dir="${match[*]:1}"

    if [ -n "$al" ] && [ ! -d "$dir" ]; then
      echo "Cleaning up: $al - $dir"
      _goto_unregister_alias "$al"
    fi
  done
}

# Changes to the given alias' directory
function _goto_directory()
{
  local target

  target=$(_goto_resolve_alias "$1")

  if [ -n "$target" ]; then
    cd "$target" || _goto_error "Failed to goto '$target'"
  fi
}

# Fetches the alias directory.
function _goto_find_alias_directory()
{
  local resolved

  resolved=$(sed -n "s/^$1 \\(.*\\)/\\1/p" "$GOTO_DB" 2>/dev/null)
  echo "$resolved"
}

# Displays the given error.
# Used for common error output.
function _goto_error()
{
  (>&2 echo "goto error: $1")
}

function _goto_print_similar()
{
  local similar
  
  similar=$(sed -n "/^$1[^ ]* .*/p" "$GOTO_DB" 2>/dev/null)
  if [ -n "$similar" ]; then
    (>&2 echo "Did you mean:")
    (>&2 echo "$similar" | column -t)
  fi
}

# Fetches alias directory, errors if it doesn't exist.
function _goto_resolve_alias()
{
  local resolved

  resolved=$(_goto_find_alias_directory "$1")

  if [ -z "$resolved" ]; then
    _goto_error "unregistered alias $1"
    _goto_print_similar "$1"
    echo ""
  else
    echo "${resolved}"
  fi
}

# Completes the goto function with the available commands
function _complete_goto_commands()
{
  local IFS=$' \t\n'

  # shellcheck disable=SC2207
  COMPREPLY=($(compgen -W "-r --register -u --unregister -l --list -c --cleanup -v --version" -- "$1"))
}

# Completes the goto function with the available aliases
function _complete_goto_aliases()
{
  local IFS=$'\n' matches al

  # shellcheck disable=SC2207
  matches=($(sed -n "/^$1/p" "$GOTO_DB" 2>/dev/null))

  if [ "${#matches[@]}" -eq "1" ]; then
    # remove the filenames attribute from the completion method
    compopt +o filenames 2>/dev/null

    # if you find only one alias don't append the directory
    COMPREPLY=("${matches[0]// *}")
  else
    for i in "${!matches[@]}"; do
      # remove the filenames attribute from the completion method
      compopt +o filenames 2>/dev/null

      if ! [[ $(uname -s) =~ Darwin* ]]; then
        matches[$i]=$(printf '%*s' "-$COLUMNS" "${matches[$i]}")

        COMPREPLY+=("$(compgen -W "${matches[$i]}")")
      else
        COMPREPLY+=("${matches[$i]// */}")
      fi
    done
  fi
}

# Bash programmable completion for the goto function
function _complete_goto()
{
  local cur="${COMP_WORDS[$COMP_CWORD]}" prev

  if [ "$COMP_CWORD" -eq "1" ]; then
    # if we are on the first argument
    if [[ $cur == -* ]]; then
      # and starts like a command, prompt commands
      _complete_goto_commands "$cur"
    else
      # and doesn't start as a command, prompt aliases
      _complete_goto_aliases "$cur"
    fi
  elif [ "$COMP_CWORD" -eq "2" ]; then
    # if we are on the second argument
    prev="${COMP_WORDS[1]}"

    if [[ $prev = "-u" ]] || [[ $prev = "--unregister" ]]; then
      # prompt with aliases only if user tries to unregister one
      _complete_goto_aliases "$cur"
    fi
  elif [ "$COMP_CWORD" -eq "3" ]; then
    # if we are on the third argument
    prev="${COMP_WORDS[1]}"

    if [[ $prev = "-r" ]] || [[ $prev = "--register" ]]; then
      # prompt with directories only if user tries to register an alias
      local IFS=$' \t\n'

      # shellcheck disable=SC2207
      COMPREPLY=($(compgen -d -- "$cur"))
    fi
  fi
}

# Register the goto compspec
if ! [[ $(uname -s) =~ Darwin* ]]; then
  complete -o filenames -F _complete_goto goto
else
  complete -F _complete_goto goto
fi
