# Moist Node - Pro Micro nRF52840

Zephyr starter firmware for a Pro Micro / SuperMini nRF52840 clone with an
existing UF2 bootloader. It blinks the onboard LED, prints status over USB, and
automatically exchanges small UDP messages with another board over OpenThread.
Flash the same firmware to both boards. BLE is not enabled.

## How the tools fit together

Each tool handles a stage in the same build pipeline:

| Tool | Role |
| --- | --- |
| west | Downloads the pinned Zephyr dependencies and starts the build. |
| CMake | Reads the application, board and configuration; generates build instructions. |
| Ninja | Runs those instructions, rebuilding only what changed. |
| Zephyr SDK | Supplies the ARM compiler and linker that produce the firmware. |

The scripts call west, which calls CMake and Ninja for you. This project uses
**upstream Zephyr**, not Nordic's nRF Connect SDK or the older nRF5 SDK.

Pinned versions: Zephyr **v4.4.0**, west **1.5.0**, Zephyr SDK **1.0.1**,
Python **3.12**. Board: `promicro_nrf52840/nrf52840/uf2`.

## Install once after cloning

Open a normal Windows PowerShell in the cloned project folder and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

This single command:

- Installs missing host tools through winget: Git, Python 3.12, CMake, Ninja,
  gperf, dtc and 7-Zip. Windows may ask you to approve an installer.
- Refreshes this process's PATH, including winget tools and 7-Zip.
- Creates an isolated Python environment and fetches pinned source dependencies.
- Installs the Python build tools and the ARM toolchain.

You need Windows App Installer (winget), internet access to GitHub/PyPI, and
several GB of free space. Existing suitable tools are reused; rerunning install
is supported. There is no need to activate Python manually or change your
permanent PowerShell policy. The command above bypasses script policy only for
that child process.

Only build-related Python packages are installed by default. The optional
`-FullTooling` flag adds Zephyr's broader test/compliance/vendor tooling.
`setup.ps1` remains a compatibility alias for the unified installer.

## Everyday commands

Run these from the project folder:

```powershell
# Incremental build: use this normally.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1

# Delete the old build and rebuild from scratch.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-clean.ps1

# Delete build outputs without rebuilding.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\clean.ps1
```

Output: **`build/zephyr/zephyr.uf2`**.
Cleaning removes only `build/`; downloaded tools and dependencies are kept.
Use clean-build when changing board/configuration or investigating stale build
results. Ordinary source edits only need the incremental build.

The scripts prevent install/build/clean from overlapping in the same workspace.
A crash releases the operation lock automatically; the presence of the
`.workspace.lock` file itself does not mean an operation is still running.

## Flash over USB

1. Connect the board with a USB data cable.
2. Briefly connect RST to GND twice quickly to enter its UF2 bootloader.
3. Find the new drive containing `INFO_UF2.TXT`.
4. Replace `F:` below with that drive letter:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\flash.ps1 -Drive F:
```

The helper copies the application UF2 to the drive. The board should reboot,
the drive should disappear, and the LED should blink. The existing bootloader
is preserved. Alternatively, drag `build/zephyr/zephyr.uf2` onto the drive.

## Read USB serial output

List COM ports, then connect using the board's application COM port:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\monitor.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\monitor.ps1 -Port COM7
```

Exit the monitor with **Esc**. Alternatively, press **Ctrl+T**, release, then **Q**.
This is a launch option in our PowerShell wrapper; installed pySerial files are unchanged.
Close the monitor before resetting/reflashing.
The monitor asserts DTR; opening it prints a fresh banner. The LED runs even
when no terminal is connected.

## Where to edit

| Location | Contents |
| --- | --- |
| `firmware/src/main.c` | Application code. |
| `firmware/prj.conf` | Enabled Zephyr features. |
| `firmware/CMakeLists.txt` | Application source list. |
| `firmware/west.yml` | Pinned Zephyr dependency manifest. |
| `deps/`, `.venv/`, `.tools/` | Downloaded sources, Python environment and SDK; ignored by Git. |
| `build/` | Generated firmware and `compile_commands.json` for editors. |

Each dependency is its own Git repository. VS Code workspace settings exclude
these folders from Git scanning. Run **Developer: Reload Window** if old entries
remain; keep the dependency `.git` directories because west needs them.

## If installation is interrupted

First rerun the same install command; completed downloads are reused. Run one
install at a time. For socket/access-denied errors, use a terminal allowed to
access the internet and installed tools. The script cannot grant itself those
permissions.

If Git reports a stale lock or an incomplete dependency checkout, stop other
Git operations and explicitly repair the named dependency, for example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -RepairDependency cmsis-dsp
```

**Repair discards local changes in that named downloaded dependency.** It
does not reset application files. Use the west project name printed in the
failure (for example, cmsis-dsp). Do not use repair to preserve dependency edits.

If winget is unavailable, install Microsoft App Installer or manually install
the host tools listed above. CMake must be 3.28+, Ninja 1.10+, and dtc 1.4.6+.
Python 3.9 can remain installed alongside the project's Python 3.12.

## Two-board OpenThread demo

1. Run `scripts\build.ps1` once, using the command above.
2. Put the first board in its UF2 bootloader and flash it using its drive letter.
3. Repeat for the second board using the **same** `build/zephyr/zephyr.uf2`.
4. Power both boards and keep them nearby for the first test. Either board can
   run from USB power without a PC or monitor attached.
5. Open one serial monitor per board, using their different COM ports. Allow
   roughly a minute for network attachment/election; independently started
   partitions can take longer to merge.

Both boards automatically form/join the `MoistNodeDemo` Thread network. The
network uses channel 15, PAN ID 4660 (0x1234), and the shared extended PAN ID and
key in `firmware/prj.conf`. These are public **lab-demo credentials**; choose
your own network/key before using the application outside this test.

The demo sends `NODE_ID seq=NUMBER hello` approximately every six seconds once
attached. UDP destination `ff03::1`, port **4242**, reaches nodes in the Thread
network, including the other board. This is a multicast demonstration; more
boards with the same settings would receive the messages too. No border router,
Wi-Fi, BLE, phone, or interactive terminal command is needed.

Example output (IDs and IPv6 addresses vary):

```text
Thread node=0123456789abcdef role=leader address=fd...:...
Thread TX seq=1 queued (error=0)
Thread RX from fd...:...: fedcba9876543210 seq=1 hello
Thread totals: TX=3 RX=2 errors=0 dropped=0
```

`leader`, `router`, and `child` are attached roles. A single powered board can
become leader and queue sends even when no peer is present. **RX messages from
the other node, or increasing RX counters on both boards, demonstrate actual
communication.** `TX queued` alone does not prove delivery. UDP has no
application acknowledgement or guaranteed delivery in this basic demo.

If a monitor is closed, messages still exchange and counters still increase;
individual packet logs are not saved for replay. On reopening, the latest totals
are displayed. The application copies received data into a small queue, keeping
USB printing outside the OpenThread callback.

Thread settings are held in RAM for this demo. After reboot each board uses the
configuration in `prj.conf` again. This deliberately avoids stale saved datasets
when experimenting; persistent provisioning and border-router integration are
future additions.

If RX remains zero: confirm both boards run this same image, compare their
network settings, check that both reach an attached role, and try rebooting them
together nearby. `detached` while searching is normal; a board remaining
`disabled` or reporting initialization failure needs investigation. Check the
`errors` and `dropped` counters for send failures or receive-queue overflow.

The application logic is in `firmware/src/thread_demo.c`; `main.c` retains the
LED/USB loop. A border router will be needed later to communicate with an
external IP network, but not for this two-board test.

References: [board documentation](https://docs.zephyrproject.org/latest/boards/others/promicro_nrf52840/doc/index.html),
[Zephyr getting started](https://docs.zephyrproject.org/latest/develop/getting_started/index.html).
