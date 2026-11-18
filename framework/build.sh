#!/usr/bin/env bash
# Compile framework classes into DEX and optionally embed them.












set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORK_DIR="$ROOT_DIR/framework"
BUILD_DIR="$FRAMEWORK_DIR/build"
CLASSES_DIR="$BUILD_DIR/classes"
DEX_PATH="$BUILD_DIR/framework.dex"
EMBED_HEADER="$ROOT_DIR/include/kudroid/framework_dex_bytes.h"

EMBED=1
REQUIRE_D8=0
for arg in "$@"; do
    [[ "$arg" == "--no-embed" ]] && EMBED=0
    [[ "$arg" == "--require-d8" ]] && REQUIRE_D8=1
done

# ── javac ────────────────────────────────────────────────────────────────────
if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/javac" ]]; then
    JAVAC="$JAVA_HOME/bin/javac"
    JAVA="$JAVA_HOME/bin/java"
else
    JAVAC="$(command -v javac || true)"
    JAVA="$(command -v java || true)"
fi
if [[ -z "$JAVAC" ]]; then
    echo "ERROR: javac not found. Install JDK or set JAVA_HOME." >&2
    exit 1
fi
echo "javac: $JAVAC"

# ── find d8 ────────────────────────────────────────────────────────────────────
# Prefer the repository-pinned compiler so Local and CI produce identical DEX
# bytes. The SDK and PATH fallbacks remain useful for developer convenience, but
# they are deliberately considered only after the pinned jar.
D8_CMD=""

if [[ -n "${KUDROID_D8_JAR:-}" && -f "$KUDROID_D8_JAR" && -n "$JAVA" ]]; then
    D8_CMD="$JAVA -cp $KUDROID_D8_JAR com.android.tools.r8.D8"
    echo "Using explicitly pinned D8: $KUDROID_D8_JAR"
elif [[ -n "$JAVA" ]]; then
    for jar in "$ROOT_DIR/third_party/d8/d8.jar" "$ROOT_DIR/third_party/d8/r8.jar"; do
        if [[ -f "$jar" ]]; then
            D8_CMD="$JAVA -cp $jar com.android.tools.r8.D8"
            echo "Using repository-pinned D8: $jar"
            break
        fi
    done
fi

if [[ "$REQUIRE_D8" == "1" && -z "$D8_CMD" ]]; then
    echo "ERROR: repository-pinned D8 is required but third_party/d8/d8.jar or r8.jar is missing." >&2
    exit 1
fi

find_d8_in_sdk() {
    local sdk="$1"
    [[ -d "$sdk/build-tools" ]] || return 1
    # Build-tools highest version has d8.
    local candidate
    candidate="$(find "$sdk/build-tools" -maxdepth 2 -name 'd8' -type f 2>/dev/null | sort -V | tail -1)"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        D8_CMD="$candidate"
        return 0
    fi
    candidate="$(find "$sdk/build-tools" -maxdepth 3 -name 'd8.jar' -type f 2>/dev/null | sort -V | tail -1)"
    if [[ -n "$candidate" && -n "$JAVA" ]]; then
        D8_CMD="$JAVA -cp $candidate com.android.tools.r8.D8"
        return 0
    fi
    return 1
}

for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
    [[ -n "$D8_CMD" ]] && break
    [[ -n "$sdk" ]] || continue
    find_d8_in_sdk "$sdk" && break
done

if [[ -z "$D8_CMD" ]] && command -v d8 > /dev/null 2>&1; then
    D8_CMD="$(command -v d8)"
fi

# Last fallback: a standalone jar placed by the user into the repo.
if [[ -z "$D8_CMD" && -n "$JAVA" ]]; then
    for jar in "$ROOT_DIR/third_party/d8/d8.jar" "$ROOT_DIR/third_party/d8/r8.jar" \
               "$ROOT_DIR/tools/d8.jar" "$ROOT_DIR/tools/r8.jar"; do
        if [[ -f "$jar" ]]; then
            D8_CMD="$JAVA -cp $jar com.android.tools.r8.D8"
            break
        fi
    done
fi

if [[ -z "$D8_CMD" ]]; then
    echo "WARNING: d8 not found (tried ANDROID_HOME, ANDROID_SDK_ROOT, PATH," >&2
    echo "third_party/d8/, tools/). Skip the step to build framework.dex." >&2
    if [[ -f "$EMBED_HEADER" ]]; then
        echo " Keep prebuilt header: $EMBED_HEADER" >&2
        exit 0
    fi
    echo "ERROR: also no prebuilt header $EMBED_HEADER — build C++ will fail." >&2
    echo " Install Android SDK build-tools or place d8.jar in third_party/d8/." >&2
    exit 1
fi
echo "d8: $D8_CMD"

# ── compile ──────────────────────────────── ────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$CLASSES_DIR"

# Avoid mapfile: macOS's default bash is 3.2.
JAVA_FILES=$(find "$FRAMEWORK_DIR" -name '*.java' -not -path "$BUILD_DIR/*" | sort)
if [[ -z "$JAVA_FILES" ]]; then
    echo "ERROR: no .java files under $FRAMEWORK_DIR" >&2
    exit 1
fi
echo "Compile $(echo "$JAVA_FILES" | wc -l | tr -d ' ') Java file..."

# Compile core classes against the framework boot classpath.


EMPTY_BOOTCLASSPATH="$BUILD_DIR/empty-bootclasspath"
mkdir -p "$EMPTY_BOOTCLASSPATH"

# -source/-target 8 (don't use --release: --release forces JDK's rt.jar
# bootclasspath and override -bootclasspath).
# shellcheck disable=SC2086
"$JAVAC" -encoding UTF-8 -nowarn -source 8 -target 8 \
    -bootclasspath "$EMPTY_BOOTCLASSPATH" \
    -d "$CLASSES_DIR" $JAVA_FILES

python3 "$ROOT_DIR/scripts/run-command.py" --timeout 60 python3 "$ROOT_DIR/scripts/fetch-legacy-http.py" --classes "$CLASSES_DIR"

# ── .class → .dex ────────────────────────────────────────────────────────────
CLASS_FILES=$(find "$CLASSES_DIR" -name '*.class' | sort)
echo "d8: $(echo "$CLASS_FILES" | wc -l | tr -d ' ') class → framework.dex"

# Keep native interface methods and merge pinned Kotlin dependencies.




KOTLIN_JARS=""
for kj in "$ROOT_DIR/third_party/kotlin/kotlin-stdlib-1.9.24.jar" \
          "$ROOT_DIR/third_party/kotlin/kotlinx-coroutines-core-jvm-1.8.0.jar"; do
    if [[ -f "$kj" ]]; then
        KOTLIN_JARS="$KOTLIN_JARS $kj"
    fi
done
if [[ -n "$KOTLIN_JARS" ]]; then
    echo "d8: merging Kotlin jars:$KOTLIN_JARS"
fi
# shellcheck disable=SC2086
$D8_CMD --min-api 29 --output "$BUILD_DIR" $CLASS_FILES $KOTLIN_JARS

# d8 always names output classes.dex.
if [[ ! -f "$DEX_PATH" ]]; then
    if [[ -f "$BUILD_DIR/classes.dex" ]]; then
        mv "$BUILD_DIR/classes.dex" "$DEX_PATH"
    else
        echo "ERROR: d8 did not generate any dex in $BUILD_DIR" >&2
        exit 1
    fi
fi

echo "Framework DEX: $DEX_PATH"
ls -lh "$DEX_PATH"

# ── embedded in C++ header ────────────────────────── ───────────────────────────
if [[ "$EMBED" == "1" ]]; then
    python3 "$ROOT_DIR/scripts/embed_framework_dex.py"
fi

echo "Done."
