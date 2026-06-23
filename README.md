# Textract

**Screen text → clipboard in one keystroke. Because pasting screenshots into an LLM is the slow, expensive path.**

A tiny, dependency-free macOS menu-bar OCR tool. Press a hotkey, drag a box over anything on your screen, and the **text** is on your clipboard — ready to paste into Claude, ChatGPT, your editor, anywhere. A free, local, open-source alternative to TextSniper, built for the era where you paste into an LLM fifty times a day.

```bash
curl -fsSL https://raw.githubusercontent.com/seanx10m/textract/main/install.sh | bash
```

That's the whole install. ~200 lines of Swift, no frameworks to download, no account, no telemetry. It builds from source in about two seconds and lives in your menu bar.

---

## Why not just screenshot it into the chat?

Because every screenshot you paste is an **image**, and images are the worst possible way to get text into a language model. You pay three taxes — tokens, latency, and accuracy — for text the model has to *guess at* anyway.

| | 📷 Paste a screenshot | ⌨️ Paste extracted text (Textract) |
|---|---|---|
| **Input tokens** (typical error / snippet) | **~1,100–1,600** on Claude · **~765+** on GPT‑4o | **~50–300** |
| **Token multiplier** | **5–20× more** | baseline |
| **Transcription** | model OCRs it — drops chars, mangles `l/1/I`, `0/O`, code, math | **exact bytes, zero guessing** |
| **Time to first token** | adds a vision-encoding pass | none |
| **Editable / greppable / diffable** | ❌ it's a picture | ✅ it's text |
| **Context-window footprint** | heavy, and re-sent every turn | light |

### The token math is not subtle

Anthropic prices an image at roughly **`(width × height) / 750`** tokens. A normal Retina region grab clamps near the cap of **~1,540 tokens** — *per image*. OpenAI's GPT‑4o counts **85 + 170 tokens per 512×512 tile**, so a 1024×1024 shot is **~765 tokens** and a bigger one is more.

That same content as text? "1 token ≈ ¾ of a word." A 50-word stack trace is **~65 tokens**. A dense paragraph is **~260**. So for the things people actually screenshot — an error, a config block, a paragraph, a snippet — you're spending **5–20× the tokens to hand the model a blurrier copy.**

> **Honest caveat:** for a *huge, dense, full-page* capture the image token count plateaus (~1.5k) while the equivalent text can exceed it. You still lose on accuracy, latency, and a context window you can't edit, grep, or diff — but if raw token count is your only metric, that's the one case where the image isn't strictly larger.

### And it's not just cost — it's your context window

In an agent loop (Claude Code, Cursor, a long ChatGPT thread), every pasted screenshot is **~1.5k tokens of context that sticks around and gets re-encoded on every turn.** Ten screenshots and you've burned 15k tokens of working memory on pictures of text you could have pasted as 1k tokens of actual text. Textract keeps your context lean and your model fast.

---

## How it works

| Shortcut | Action |
|---|---|
| **⌘⇧2** | Capture a screen region → OCR → text on clipboard |
| **⌘⇧1** | OCR an image already on your clipboard |

Press **⌘⇧2**, the native macOS crosshair appears, drag a box, and the recognized text is on your clipboard with a small ✓ toast. Cancel with `Esc` and nothing changes. That's it.

OCR is done **100% on-device** with Apple's Vision framework — nothing leaves your Mac.

### Menu-bar options (the `T` icon)

- **Capture Hotkey** — `⌘⇧2`, `⌥⌘T`, or `⌃⌥⌘Space`
- **OCR Language** — Automatic + 9 languages
- **Keep Line Breaks** — preserve layout or collapse to a single line
- **Launch at Login** — always-on, like a real utility

---

## Install

**One command:**

```bash
curl -fsSL https://raw.githubusercontent.com/seanx10m/textract/main/install.sh | bash
```

**Or from source:**

```bash
git clone https://github.com/seanx10m/textract.git
cd textract
./build.sh
cp -R build/Textract.app ~/Applications/
open ~/Applications/Textract.app
```

**Requirements:** macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). No other dependencies.

### First-run permission

The first time you capture, macOS asks for **Screen Recording** permission — grant it, then **quit & reopen Textract once** so the grant takes effect:

```bash
pkill -x Textract; sleep 1; open ~/Applications/Textract.app
```

If you build with a code-signing identity (Apple Development / Developer ID), this grant persists across future rebuilds. With ad-hoc signing it resets each rebuild — fine for a one-time install.

---

## Notes

- Menu-bar only (no Dock icon). Quit via the `T` menu, Activity Monitor, or `pkill -x Textract`.
- The hotkeys work even if the menu-bar icon is hidden behind the notch.
- Not affiliated with AWS Textract — different tool, same obvious name.

## License

MIT © 2026 Sean Muse
