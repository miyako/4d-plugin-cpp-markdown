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
