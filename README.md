# Dell brightness stuck — brightness slider moves but the screen never changes

> **Verified fix, tested on a Dell G15 5530 (i7-13650HX + RTX 4060 Laptop).**
> Brightness was frozen at one level. Slider moved 0–100 %, `Fn` keys did nothing, switching to the dGPU did nothing, reinstalling the Intel driver did nothing. This repo is the diagnosis that found the real cause, and the fix.

<p>
<img alt="Windows 11" src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white">
<img alt="Dell" src="https://img.shields.io/badge/Dell-G15%205530-007DB8">
<img alt="NVIDIA" src="https://img.shields.io/badge/NVIDIA-Advanced%20Optimus-76B900?logo=nvidia&logoColor=white">
<img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white">
</p>

---

## TL;DR (English)

On Dell gaming laptops with an **eDP MUX / NVIDIA Advanced Optimus**, the internal panel's backlight is not owned by the Intel driver alone — it is shared with **NVPCF**, the *NVIDIA Platform Controllers and Framework* device (`ACPI\NVDA0820\NPCF`).

If that device is in a **failed-install** state — typically after using DDU, or after installing *only* the Intel graphics driver — Windows still accepts brightness commands and happily echoes them back, but the value never reaches the panel. The slider moves. Nothing happens.

**Fix:** install the **Dell** NVIDIA driver package for your exact model. That binds NVPCF and the backlight comes back.

```powershell
# elevated
& "NVIDIA-GeForce-RTX-4060-4050-3050-Graphics-Driver_YX6KM_WIN64_32.0.16.1687_A17.exe" -s
```

---

## বাংলায় সারমর্ম

MUX / Advanced Optimus থাকা Dell ল্যাপটপে প্যানেলের ব্যাকলাইট শুধু Intel ড্রাইভারের হাতে থাকে না — **NVPCF** (`NVIDIA Platform Controllers and Framework`, ডিভাইস `ACPI\NVDA0820\NPCF`) এর সাথে ভাগ করা।

DDU দিয়ে সব মুছলে, বা **শুধু Intel ড্রাইভার** ইনস্টল করলে, এই NVPCF ডিভাইসটা **failed-install** অবস্থায় পড়ে থাকে। তখন Windows brightness কমান্ড গ্রহণ করে, মান ফেরতও দেয় — কিন্তু সেটা প্যানেলে পৌঁছায় না। স্লাইডার নড়ে, পর্দা স্থির।

**সমাধান:** আপনার মডেলের জন্য **Dell-এর** NVIDIA ড্রাইভার প্যাকেজ ইনস্টল করুন। NVPCF বাইন্ড হয়ে যায়, ব্যাকলাইট ফিরে আসে।

---

## Symptom

| | |
|---|---|
| Brightness slider | moves 0–100 %, no visual effect |
| `Fn` + brightness keys | no effect |
| Switching to dGPU-only | no effect |
| Reinstalling Intel graphics driver | no effect |
| Device Manager → Display adapters | **two** entries reading *Microsoft Basic Display Adapter* |
| Windows brightness value | changes and persists, panel does not follow |

## Tested environment

| | |
|---|---|
| Laptop | Dell G15 5530 (G-Series, SKU 0BF7) |
| CPU | Intel Core i7-13650HX |
| GPU | Intel UHD Graphics (`PCI\VEN_8086&DEV_A78B`) + NVIDIA RTX 4060 Laptop (`PCI\VEN_10DE&DEV_28E0`) |
| Panel | AUO AA9F, 1920 × 1080 @ 360 Hz, internal eDP |
| OS | Windows 11 Pro build 26300 |
| BIOS | 1.36.0 |

---

## Diagnosis (read-only, run this first)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\diagnose.ps1
# add -TestBrightness to also do a live backlight write test
```

What to look for — these four lines together **are** the diagnosis:

```
3. PNP DISPLAY DEVICES
  Error   Microsoft Basic Display Adapter
          problem  CM_PROB_FAILED_START (This device cannot start. (Code 10).)

4. NVIDIA PLATFORM CONTROLLERS AND FRAMEWORK
  status   Error
  problem  CM_PROB_FAILED_INSTALL

6. INSTALLED NVIDIA COMPONENTS
  NVIDIA Platform Controllers and Framework    615.34      <-- "installed", yet the device failed

7. eDP MUX INDICATOR
  ParadeMuxEdpLinkRateDataReloadTrigger        1           <-- MUX hardware present
```

That combination — **a "successfully installed" component whose device is in failed-install state** — is the half-installed signature. The uninstall entry proves the installer ran; the device state proves it never bound.

### The tell that saves you time

Run the live write test and watch the screen:

```
set 100%  ->  read back 100%
set  50%  ->  read back  50%
set  10%  ->  read back  10%
```

The ACPI backlight interface is **working perfectly** — it accepts and returns every value. The panel still does not change. That means the problem is **not** the ACPI path, not the slider, not a Windows bug. Something else owns the physical backlight. That "something else" is NVPCF.

If instead the read-back did **not** follow your write, your problem is in the Intel driver/ACPI path and this guide does not apply.

---

## The fix

> Requires administrator. Your screen will flicker once or twice.

1. **Get the Dell package for your exact model.** Go to `dell.com/support` → enter your Service Tag → *Drivers & Downloads* → *Video*. Download the NVIDIA graphics driver. Do not grab a generic driver from nvidia.com for this repair — the Dell package is the one that also carries the platform/NVPCF components for your board.
2. **Run it elevated and silent:**
   ```powershell
   Start-Process -FilePath "C:\path\to\NVIDIA-GeForce-RTX-4060-4050-3050-Graphics-Driver_..._A17.exe" `
                 -ArgumentList '-s' -Verb RunAs -Wait
   ```
   It extracts roughly 1 GB and takes 5–10 minutes. **Exit code 0** means success.
3. **Verify:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
   ```
   All checks must be `[PASS]`.
4. **Reboot** once, then move the brightness slider.

### What actually changes

| Before | After |
|---|---|
| `Microsoft Basic Display Adapter`, Code 10 | `NVIDIA GeForce RTX 4060 Laptop GPU`, driver `32.0.16.1687` |
| `ACPI\NVDA0820\NPCF` → `CM_PROB_FAILED_INSTALL` | → `OK` (*NVIDIA Platform Controllers and Framework*) |
| `NVDisplay.ContainerLocalSystem` absent | → `Running` |
| backlight frozen | **backlight responds** |

---

## If it ever comes back — 30-second checklist

1. Device Manager → **Display adapters**. Is either entry called *Microsoft Basic Display Adapter*?
   → an adapter has no driver. Install the Dell package for it.
2. Device Manager → **System devices** → *NVIDIA Platform Controllers and Framework*. Does it show a warning triangle (Code 28 / failed install)?
   → run the Dell NVIDIA package again.
3. Only after both are clean, look anywhere else.

**Rule that prevents 90 % of these cases:** after DDU, install **both** drivers — Intel **and** NVIDIA. Installing only one leaves NVPCF unbound, and brightness stays dead even though everything "looks" installed.

---

## Fresh Windows install

1. Install Windows, then the Dell driver set (chipset, Intel graphics, NVIDIA graphics, audio, network).
2. Check the two items from the checklist above.
3. Done — no registry tweaks, no scripts.

Do **not** follow guides that tell you to set `FeatureTestControl` or other undocumented display registry values. They are leftovers from the Windows 7 era, they do not apply to modern DCH drivers, and on a MUX machine they can make things worse.

## What did **not** fix it (verified, don't waste your evening)

- ❌ Reinstalling the Intel graphics driver alone
- ❌ Switching the preferred GPU to the dGPU
- ❌ DDU + Intel-only reinstall
- ❌ Changing power plan / adaptive brightness (already off)
- ❌ Editing Intel `FeatureTestControl`

All of them leave NVPCF unbound, so the backlight path stays broken.

---

## Why this happens (background)

Advanced Optimus puts a physical multiplexer between the two GPUs and the internal panel. Whoever drives the panel also owns its backlight, and the EC that physically drives the backlight PWM speaks to the **NVIDIA** platform driver, not to the Intel display driver — even when the Intel GPU is the one scanning out the image.

That is why the Intel ACPI backlight object answers every command: it is a valid object, writing to a path that is currently muxed away. The write succeeds. The photons do not move.

---

## Files

| File | Purpose |
|---|---|
| `scripts/diagnose.ps1` | read-only diagnosis, optional live backlight test |
| `scripts/verify.ps1` | PASS/FAIL verification after the fix |

## License

MIT — see [LICENSE](LICENSE). Provided as-is; you are modifying your own machine's drivers.
