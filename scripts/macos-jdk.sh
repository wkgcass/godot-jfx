# Source from a macOS entry point before it handles its own arguments.
# Consume --jdk while preserving the order and quoting of the other arguments.
remaining_jdk_args=$#
while [ "$remaining_jdk_args" -gt 0 ]; do
    case "$1" in
        --jdk)
            if [ "$remaining_jdk_args" -lt 2 ] || [ -z "${2-}" ]; then
                echo "--jdk requires a JDK home directory" >&2
                exit 2
            fi
            JAVA_HOME=$2
            shift 2
            remaining_jdk_args=$((remaining_jdk_args - 2))
            ;;
        *)
            set -- "$@" "$1"
            shift
            remaining_jdk_args=$((remaining_jdk_args - 1))
            ;;
    esac
done
unset remaining_jdk_args
: "${JAVA_HOME:?Set JAVA_HOME to JDK 25 or pass --jdk DIRECTORY}"
if [ ! -x "$JAVA_HOME/bin/java" ] || [ ! -x "$JAVA_HOME/bin/javac" ]; then
    echo "Expected a JDK with bin/java and bin/javac at $JAVA_HOME" >&2
    exit 1
fi
case "$JAVA_HOME" in
    /*) ;;
    *) JAVA_HOME=$(CDPATH= cd "$JAVA_HOME" && pwd -P) || exit 1 ;;
esac
export JAVA_HOME
case "$(uname -s)" in
    Linux) native_driver=vulkan; native_prism=es2; source_editor=godot.linuxbsd.editor.x86_64 ;;
    Darwin) native_driver=metal; native_prism=mtl; source_editor=godot.macos.editor.arm64 ;;
    *) echo "Unsupported Unix desktop platform" >&2; exit 2 ;;
esac
check_desktop_driver() {
    case "$1" in "$native_driver"|opengl) ;; *) echo "expected --driver $native_driver or opengl" >&2; return 2 ;; esac
}
