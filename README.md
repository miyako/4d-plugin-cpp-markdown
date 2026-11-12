![version](https://img.shields.io/badge/version-18%2B-EB8E5F)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-cpp-markdown)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-cpp-markdown/total)


# 4d-plugin-cpp-markdown

**CPP Markdown** is a 4D plugin that converts Markdown-formatted text into HTML. It is a thin wrapper around the open-source [cpp-markdown](https://github.com/sevenjay/cpp-markdown) C++ library, exposed to 4D code as a single command.

The plugin takes one text parameter containing Markdown source and returns a text value containing the equivalent HTML. It performs no file I/O, no network access, and no changes to your 4D database — it is a pure text-in / text-out conversion.

**Requirements:** 4D v18 or later. Available for macOS (Intel & Apple Silicon) and Windows 64-bit.

---

## Command Reference

### `CPP Markdown`

Converts a Markdown string to HTML.

**Syntax**

```
CPP Markdown ( markdownText ) -> Function result
```

| Parameter | Type | Description |
|---|---|---|
| `markdownText` | Text | The Markdown source to convert. |
| **Function result** | Text | The generated HTML. |

**Notes**

- The command is thread-safe and may be called from preemptive processes.
- Input larger than **1 MB** is rejected and returns an empty string, as a safeguard against excessive processing time on very large or malformed input. If you need to convert larger documents, split them into smaller chunks (e.g., per section) and concatenate the resulting HTML.
- If the Markdown cannot be parsed for any reason, the command returns an empty string rather than raising an error in your 4D code. Always check whether the result is empty if the outcome matters to your logic.
- The command does not wrap the output in `<html>`/`<body>` tags — it returns only the converted fragment, so you can embed it directly into a larger HTML page or template.

---

## Usage

1. Build your Markdown text as a 4D Text variable (or read it from a file, a field, a web request body, etc.).
2. Pass it to `CPP Markdown`.
3. Use the returned HTML string — e.g., display it in a 4D Web Area, save it to an `.html` file, insert it into an email body, or store it in a database field.

---

## Sample Code

### Basic conversion

```4d
var $markdown; $html : Text

$markdown:="# Hello World\n\nThis is **bold** and this is *italic*."
$html:=CPP Markdown($markdown)

 // $html now contains:
 // <h1>Hello World</h1>
 // <p>This is <strong>bold</strong> and this is <em>italic</em>.</p>
```

### Converting a list

```4d
var $markdown; $html : Text

$markdown:="# header"+Char(Carriage return)+"* item"+Char(Carriage return)+"* item"
$html:=CPP Markdown($markdown)

TRACE
```

### Displaying the result in a Web Area

```4d
var $markdown; $html : Text

$markdown:=Document to text(Select document(""))  // load a .md file the user picks
$html:=CPP Markdown($markdown)

WA SET HTML VALUE(*; "MyWebArea"; $html)
```

### Guarding against oversized or unparsable input

```4d
var $markdown; $html : Text

$markdown:=Document to text($path)

If (Length($markdown)>1*1024*1024)
	ALERT("This document is too large to convert (limit: 1 MB).")
Else
	$html:=CPP Markdown($markdown)
	If ($html="")
		ALERT("The document could not be converted. Please check its formatting.")
	Else
		 // use $html
	End if 
End if 
```

### Saving converted HTML to a file

```4d
var $markdown; $html : Text
var $path : Text

$markdown:="## Report Summary"+Char(Carriage return)+"All checks passed."
$html:=CPP Markdown($markdown)

$path:=System folder(Desktop)+"summary.html"
TEXT TO DOCUMENT($path; $html)
```

---

## Supported Markdown Syntax

CPP Markdown supports the common Markdown constructs, including:

- Headers (`#` through `######`)
- Bold (`**text**`) and italic (`*text*`)
- Unordered lists (`*`, `-`, `+`) and ordered lists (`1.`, `2.`, ...)
- Links (`[text](url)`) and images (`![alt](url)`)
- Blockquotes (`>`)
- Inline code (`` `code` ``) and fenced/indented code blocks
- Horizontal rules (`---`)

For the full syntax reference and examples, see: [miyako.github.io/2019/12/13/4d-plugin-cpp-markdown.html](https://miyako.github.io/2019/12/13/4d-plugin-cpp-markdown.html)

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Result is an empty string | Input exceeded 1 MB, or the Markdown could not be parsed | Check input size; simplify or validate the Markdown |
| Unexpected HTML formatting | Markdown source has ambiguous or non-standard syntax | Test the same input against a standard Markdown reference to confirm expected output |
| No response / delay on very large input | Extremely large or deeply nested input can take longer to process even under the 1 MB cap | Break large documents into smaller sections and convert each separately |

## Maintainer ownership regression

On macOS, run `python3 tests/ownership/run.py`. This unsigned synthetic test
compiles the complete bundled SDK, all wrapper implementations, the JSON
helpers, and the real exported dispatcher and Markdown parser. It does not
invoke Xcode/MSBuild, the release workflows, or a 4D installation. Engine
selectors and command IDs are allowlisted; path and drawing boundaries throw,
and executable imports are checked before execution. Fixtures are in memory.
The only non-system library is the bundled universal Boost.Regex archive
(SHA-256 `5a7f1035febc9361af788834d081e749b0eadd86edc36d7b00f61dea5cc2ad5c`);
no dependency installation or network operation is part of the test.

The ownership audit baseline is
`f57992aec7f65f7f9c1b96aa460c2e26abcf6606`. Both native projects compile only
the SDK, `C_TEXT`, dispatcher, and parser. The manifest has one scalar text
command and **no array signatures**. `ARRAY_TEXT`, `C_BLOB`, `C_LONGINT`, and
`support/4DPlugin-JSON.cpp` are dormant support code, with no dispatcher,
parser, callback, or internal command consumers. The exported command has
no reachable array-transfer defect. Its source and `C_TEXT` implementation
are unchanged.

The dormant JSON fixes avoid overwriting initialized empty string/picture
owners, clear successful property results (including type mismatches), and
capture SDK errors before adopting or inspecting property/command outputs.
Property helpers and `ob_stringify` now throw `std::runtime_error` on SDK
failure instead of silently consuming an unspecified result. Existing
successful type-mismatch defaults remain unchanged. `ob_get_c` transfers
its successful collection result owner to the caller, which must call
`PA_DisposeCollection`. Picture/object/collection setters retain their
existing consume-the-supplied-owner semantics; do not pass borrowed values.
`ARRAY_TEXT` and `C_BLOB` reject raw-pointer shallow copies, matching the
existing `C_TEXT` restriction. No production copy-related crash is claimed.

The same harness against a `git archive` of the immutable baseline reports
**169 checks, 31 failures, 138 passing controls**; fixed sources report
**169 checks, zero failures**. Baseline failures are:

| Named failure | Count |
|---|---:|
| ARRAY_TEXT / C_BLOB shallow owner copy traits | 2 |
| Narrow setter isolated owner balance | 4 |
| Narrow setter/getter owner balance | 4 |
| Wide-key string setter owner balance | 4 |
| Wide-value / native UTF-16 / picture setter owner balance | 3 |
| All getter success/type-mismatch owner balance | 3 |
| Failed duplicate/stringify command adoption | 2 |
| Failed property-existence command reporting | 5 |
| Failed property result adoption | 4 |

Controls include ASCII, BMP and supplementary characters, empty strings,
UTF-16 lengths and termination, capacity/reuse boundaries, explicit string,
handle, picture and reference-owner balances, collection handoff, array
index zero, accepted independent transfers, allocator churn, rejected
kind/index/null-data/null-input assignments, resize/clear, actual dispatcher
HTML, and the oversized-input guard. The array setter is tested unchanged:
accepted descriptors transfer ownership and rejected descriptors remain
caller-owned; getter descriptors are borrowed and snapshots copy content.
No cleanup is removed from synchronous SDK callbacks.

SDK implementation/ABI files remain unchanged. Baseline Git blob identities:

| File in `4D Plugin API/` | Git blob |
|---|---|
| `4DPluginAPI.c` | `62f745e91d81ef2c3c901c656ea8e175d3b173e8` |
| `4DPluginAPI.h` | `528bf1d2552df08d6a8b1bc95011a9b72934ad5c` |
| `PrivateTypes.h` | `a3098cb662cdbc43ba574fdef72a059c4c6d1cd4` |
| `PublicTypes.h` | `9ae20b001bff9128f690fff3e6c3f873b6238333` |
| `EntryPoints.h` | `da428d5f6ca23b0a30371c7288a01d29aa3c466a` |
| `Flags.h` | `7a5a35539f27430a3fd9cb711d6b789051316471` |

Canonical guidance was read at immutable and current revision
`e6b492fcb81e5e1a7f7db723594b420e63bf6eb9` of
`miyako/skills/4d-skills/skills/4dplugin/SKILL.md`.
ASan and UBSan run with packed SDK alignment excluded; macOS LSan is
disabled and explicit owner accounting is used instead. The synthetic host
uses allocated empty strings/pictures and independently owned successful
property results. Failed outputs use a permissible raw-type-zero poison,
not an assumed failure-output contract. Actual macOS/Windows 4D execution,
native Windows compilation, other unspecified failure-output shapes,
OOM/resize failure and malformed metadata contracts remain unverified.
The prebuilt Boost.Regex dependency is not sanitizer-instrumented.
Deployment builds, signing, notarization, binary packaging and release
publication are not part of this regression workflow.
