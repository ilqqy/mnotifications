import QtQuick
import Quickshell
import "text.js" as Format

// Run through tests/markup.sh, which puts text.js beside this file.
// Prints one line per case and a summary line.
ShellRoot {
    readonly property var cases: [
        ["allowed tags kept", "<b>bold</b> <i>it</i> <u>u</u>", "<b>bold</b> <i>it</i> <u>u</u>"],
        ["tag names are case-insensitive", "<B>caps</B>", "<b>caps</b>"],
        ["https link kept", "<a href=\"https://example.org\">link</a>", "<a href=\"https://example.org\">link</a>"],
        ["single-quoted href", "<a href='https://example.org'>s</a>", "<a href=\"https://example.org\">s</a>"],
        ["mailto link kept", "<a href=\"mailto:a@b.c\">mail</a>", "<a href=\"mailto:a@b.c\">mail</a>"],
        ["javascript href dropped", "<a href=\"javascript:alert(1)\">x</a>", "x"],
        ["file href dropped", "<a href=\"file:///etc/passwd\">x</a>", "x"],
        ["extra attributes dropped", "<a href=\"https://x.org\" onclick=\"evil()\" style=\"x\">t</a>", "<a href=\"https://x.org\">t</a>"],
        ["href entities re-escaped", "<a href=\"https://a.b/?x=1&amp;y=2\">q</a>", "<a href=\"https://a.b/?x=1&amp;y=2\">q</a>"],
        ["quote in href cannot break out", "<a href='https://x.org/\"><img src=x>'>t</a>", "<a href=\"https://x.org/&quot;&gt;&lt;img src=x&gt;\">t</a>"],
        ["nested link flattened", "<a href=\"https://1.org\"><a href=\"https://2.org\">x</a></a>", "<a href=\"https://1.org\">x</a>"],
        ["img becomes alt text", "<img src=\"file:///etc/passwd\" alt=\"ALT\"/>", "ALT"],
        ["img without alt vanishes", "a<img src=\"https://tracker/p.png\">b", "ab"],
        ["img alt is escaped", "<img alt=\"&lt;b&gt;x\">", "&lt;b&gt;x"],
        ["entities preserved", "&amp; 1 &lt; 2 &gt; 0", "&amp; 1 &lt; 2 &gt; 0"],
        ["numeric entities", "&#60;b&#62; &#x263A;", "&lt;b&gt; ☺"],
        ["bare ampersand escaped", "Tom & Jerry", "Tom &amp; Jerry"],
        ["unknown entity kept literally", "&bogus;", "&amp;bogus;"],
        ["loose angle brackets escaped", "x < y > z", "x &lt; y &gt; z"],
        ["heart emoticon survives", "I <3 it", "I &lt;3 it"],
        ["unknown tag shown literally", "<foo>bar</foo>", "&lt;foo&gt;bar&lt;/foo&gt;"],
        ["known tag stripped, text kept", "<span style=\"color:red\">red</span> <font color=\"red\">f</font>", "red f"],
        ["script content dropped", "<script>alert(1)</script>ok", "ok"],
        ["style content dropped", "<style>b{}</style>ok", "ok"],
        ["unclosed script drops the rest", "a<script>evil", "a"],
        ["quotes escaped", "\"q\" 'a'", "&quot;q&quot; &#39;a&#39;"],
        ["newlines become breaks", "line1\nline2\r\nline3", "line1<br>line2<br>line3"],
        ["br variants", "a<br/>b<br>c<BR />d", "a<br>b<br>c<br>d"],
        ["misnesting balanced", "<b><i>x</b>y</i>", "<b><i>x</i></b><i>y</i>"],
        ["unclosed tag closed at end", "<b>unclosed", "<b>unclosed</b>"],
        ["stray closing tag dropped", "</b>stray</a>", "stray"],
        ["empty", "", ""],
        ["null-ish input", undefined, ""]
    ]

    readonly property var times: [
        [0, "now"],
        [59 * 1000, "now"],
        [60 * 1000, "1m ago"],
        [59 * 60 * 1000, "59m ago"],
        [2 * 3600 * 1000, "2h ago"],
        [3 * 86400 * 1000, "3d ago"],
        [-5000, "now"]
    ]

    Component.onCompleted: {
        let failed = 0;
        for (const [name, input, expected] of cases) {
            const actual = Format.sanitize(input);
            const ok = actual === expected;
            if (!ok) failed++;
            console.log((ok ? "PASS " : "FAIL ") + name + (ok ? "" : "\n  input:    " + JSON.stringify(input)
                + "\n  expected: " + JSON.stringify(expected) + "\n  actual:   " + JSON.stringify(actual)));
        }
        const long = Format.sanitize("<b>" + "x".repeat(10000));
        const capped = long === "<b>" + "x".repeat(3997) + "</b>";
        if (!capped) failed++;
        console.log((capped ? "PASS " : "FAIL ") + "input capped at 4000 characters");
        for (const [age, expected] of times) {
            const actual = Format.relativeTime(1000000000, 1000000000 + age);
            const ok = actual === expected;
            if (!ok) failed++;
            console.log((ok ? "PASS " : "FAIL ") + "relativeTime " + age + " -> " + actual);
        }
        // Quickshell does not forward Qt.exit codes; the runner reads this line.
        console.log(failed === 0 ? "markup: all passed" : "markup: " + failed + " failed");
        Qt.quit();
    }
}
