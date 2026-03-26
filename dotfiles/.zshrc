# Portable zsh configuration.

export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
fi

if [ -r "$HOME/.antidote/antidote.zsh" ]; then
  source "$HOME/.antidote/antidote.zsh"
  antidote load
fi

if [ -s "$NVM_DIR/bash_completion" ]; then
  . "$NVM_DIR/bash_completion"
fi

autoload -U promptinit
promptinit
if whence -w prompt_pure_setup >/dev/null 2>&1; then
  prompt pure
fi

set_java_home() {
  target_home=$1
  if [ -n "${target_home:-}" ]; then
    if [ -n "${JAVA_HOME:-}" ]; then
      path=("${(@)path:#"$JAVA_HOME/bin"}")
    fi
    export JAVA_HOME="$target_home"
    path=("$JAVA_HOME/bin" "${path[@]}")
  fi
}

unset JAVA_HOME
if command -v /usr/libexec/java_home >/dev/null 2>&1; then
  export JAVA8_HOME="$(/usr/libexec/java_home -v1.8 2>/dev/null || true)"
  export JAVA11_HOME="$(/usr/libexec/java_home -v11 2>/dev/null || true)"
  export JAVA17_HOME="$(/usr/libexec/java_home -v17 2>/dev/null || true)"
fi

alias jdk_11='set_java_home "$JAVA11_HOME"'
alias jdk_8='set_java_home "$JAVA8_HOME"'
alias jdk_17='set_java_home "$JAVA17_HOME"'

if [ -n "$JAVA17_HOME" ]; then
  jdk_17
elif [ -n "$JAVA11_HOME" ]; then
  jdk_11
fi
