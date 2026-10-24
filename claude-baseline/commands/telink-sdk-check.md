Verify the Telink SDK mount and report exactly what is and is not usable.

Run this **first** in any Telink session. The tc32 toolchain is not in the
image — it lives inside the EULA-restricted SDK, which must be host-mounted —
so almost every Telink failure traces back to this.

Execute and show all output:

```bash
echo "=== SDK mount ==="
SDK="${SDK:-/opt/telink/sdk}"
if [ -d "$SDK" ] && [ -n "$(ls -A "$SDK" 2>/dev/null)" ]; then
    echo "mounted: $SDK"
    ls "$SDK" | head -20
else
    echo "NOT MOUNTED (or empty): $SDK"
fi

echo ""
echo "=== tc32 toolchain ==="
ls -la "$SDK/tools/tc32/bin/" 2>/dev/null | head -20 || echo "(no tools/tc32/bin)"
"$SDK/tools/tc32/bin/tc32-elf-gcc" --version 2>&1 | head -3 \
    || echo "tc32-elf-gcc will not execute"

echo ""
echo "=== 32-bit runtime (the tc32 blob is a 32-bit binary) ==="
ls /usr/lib32/libc.so.6 2>/dev/null && echo "lib32-glibc present" \
    || echo "MISSING 32-bit glibc"
file "$SDK/tools/tc32/bin/tc32-elf-gcc" 2>/dev/null || true

echo ""
echo "=== PATH ==="
echo "$PATH" | tr ':' '\n' | grep -n tc32 || echo "tc32 not on PATH"
command -v tc32-elf-gcc || echo "tc32-elf-gcc not resolvable"

echo ""
echo "=== SWS flashing tools ==="
ls "${TLSR_TOOLS:-/opt/telink/tlsr-tools}" 2>/dev/null | head \
    || echo "(no community flashing tools)"

echo ""
echo "=== serial adapters (SWS needs a USB-serial adapter) ==="
ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "(none)"

echo ""
echo "=== workspace profile ==="
mcu --list 2>/dev/null || echo "(no .mcu-profile.json here)"

echo ""
echo "=== dev-doctor (telink checks) ==="
dev-doctor 2>/dev/null | grep -E "telink|tc32|lib32|tlsr" || true
```

## Report

State plainly which of these is true, and do not proceed to build if the first
one is:

1. **SDK not mounted.** Nothing can be compiled. The fix is on the host:

   ```bash
   ./scripts/dev-up.sh                       # auto-mounts ~/telink/Telink_825X_SDK
   DEV_TELINK_SDK=/path/to/sdk ./scripts/dev-up.sh
   ```

   The SDK is not redistributable, so it cannot be baked into the image. The
   open mirror is [Ai-Thinker-Open/Telink_825X_SDK](https://github.com/Ai-Thinker-Open/Telink_825X_SDK).

2. **SDK mounted but `tools/tc32/bin/tc32-elf-gcc` missing.** The mount points
   at the wrong directory level — it should be the SDK root, the directory that
   *contains* `tools/`.

3. **`tc32-elf-gcc` present but will not execute.** Missing 32-bit runtime. That
   would mean the image was built wrong (`lib32-glibc` is installed by the
   Dockerfile); report it as an image bug rather than a user error.

4. **Everything present.** Report the tc32 version and move on.

## Also worth saying, once, up front

Be honest about the state of this leaf compared with `arm` and `wch`:

- **Flashing** in-container relies on community SWS tools and a USB-serial
  adapter. Telink's own BDT is a Windows GUI and cannot run here. Verify on a
  scratch board before trusting it.
- **There is no supported in-container GDB server for TC32.** The profile's
  `debugServer` task deliberately exits non-zero rather than pretending. Plan on
  UART tracing, or debug from Windows with BDT.
- The `tlsr-otp-vs-flash` skill matters before the first write — OTP is
  one-shot, and there is no recovery from a wrong one.
