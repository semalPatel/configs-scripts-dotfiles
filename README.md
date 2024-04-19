# dot-files-scripts
Collection of scripts as well some config files for repetitive tasks. This is a continuous list.

##### Easily switch JDK Versions

```java
unset JAVA_HOME
export JAVA8_HOME="$(/usr/libexec/java_home -v1.8)"
export JAVA11_HOME="$(/usr/libexec/java_home -v11)"
alias jdk_11='export JAVA_HOME="$JAVA11_HOME" && export PATH="$PATH:$JAVA_HOME/bin"'
alias jdk_8='export JAVA_HOME="$JAVA8_HOME" && export PATH="$PATH:$JAVA_HOME/bin"'
# jdk_11 # Use jdk 11 as the default jdk
jdk_8  # Mobile dev still needs jdk 8 :/
```
