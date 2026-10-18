.pragma library

// Body markup and timestamps.
//
// The notification spec lets a body carry <b>, <i>, <u>, <a href> and <img>.
// sanitize() rebuilds the body from scratch for Text.StyledText: the four
// formatting tags are re-emitted in canonical form, <img> becomes its alt
// text (the server does not advertise body-images), <br> and newlines become
// line breaks, script/style content is dropped, every other recognised HTML
// tag is removed with its text kept, and everything else is escaped. Nothing
// the sender wrote reaches the renderer unescaped, so no tag, attribute or
// image URL survives that is not produced here.

const ESCAPES = {"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"};
const NAMED_ENTITIES = {"amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u00a0"};

// Tag names treated as markup. A "<word>" whose name is not listed here is
// shown literally, so plain-text bodies like "if a<b>c" lose nothing they
// would not lose in any HTML renderer, and "<3" or "x < y" are untouched.
const KNOWN_TAGS = new Set([
    "a", "abbr", "b", "big", "blockquote", "body", "br", "center", "cite",
    "code", "dd", "del", "div", "dl", "dt", "em", "embed", "font", "h1", "h2",
    "h3", "h4", "h5", "h6", "head", "hr", "html", "i", "iframe", "img", "ins",
    "kbd", "li", "link", "mark", "meta", "object", "ol", "p", "pre", "q", "s",
    "samp", "script", "small", "span", "strike", "strong", "style", "sub",
    "sup", "svg", "table", "tbody", "td", "th", "thead", "title", "tr", "tt",
    "u", "ul", "var"
]);

// Name, then attributes in which quoted values may contain < and >.
const TAG = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:\s(?:[^<>"']|"[^"]*"|'[^']*')*?)?)\s*(\/?)>/g;

// Bodies are capped before parsing; banners show a few lines at most.
const MAX_INPUT = 4000;

function escapeHtml(s) {
    return s.replace(/[&<>"']/g, c => ESCAPES[c]);
}

function decodeEntities(s) {
    return s.replace(/&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,6});/g, (match, entity) => {
        if (entity[0] === "#") {
            const hex = entity[1] === "x" || entity[1] === "X";
            const code = parseInt(entity.slice(hex ? 2 : 1), hex ? 16 : 10);
            const valid = code > 0 && code <= 0x10ffff && (code < 0xd800 || code > 0xdfff);
            return valid ? String.fromCodePoint(code) : match;
        }
        return NAMED_ENTITIES[entity] ?? match;
    });
}

function plain(s) {
    return escapeHtml(decodeEntities(s)).replace(/\r\n|\r|\n/g, "<br>");
}

function attribute(attrs, name) {
    const re = new RegExp("(?:^|\\s)" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+))", "i");
    const m = re.exec(attrs);
    return m ? decodeEntities(m[1] ?? m[2] ?? m[3] ?? "") : null;
}

function safeHref(href) {
    if (href === null) return null;
    const trimmed = href.trim();
    return /^(https?:\/\/|mailto:)/i.test(trimmed) ? trimmed : null;
}

function sanitize(input) {
    const source = String(input ?? "").slice(0, MAX_INPUT);
    // Open formatting elements, innermost last. A link whose href was
    // rejected is tracked as "a-plain" so its closing tag is swallowed.
    const open = [];
    let out = "";
    let last = 0;
    let skipUntil = null;
    let m;

    TAG.lastIndex = 0;
    while ((m = TAG.exec(source)) !== null) {
        const name = m[2].toLowerCase();
        const closing = m[1] === "/";
        const attrs = m[3] ?? "";
        const between = source.slice(last, m.index);
        last = TAG.lastIndex;

        if (skipUntil !== null) {
            if (closing && name === skipUntil) skipUntil = null;
            continue;
        }

        out += plain(between);

        if (!KNOWN_TAGS.has(name)) {
            out += plain(m[0]);
            continue;
        }

        switch (name) {
        case "b":
        case "i":
        case "u":
            if (!closing) {
                out += "<" + name + ">";
                open.push(name);
            } else {
                out += closeElement(open, name);
            }
            break;
        case "a":
            if (!closing) {
                const href = open.some(t => t === "a" || t === "a-plain")
                    ? null
                    : safeHref(attribute(attrs, "href"));
                if (href !== null) {
                    out += "<a href=\"" + escapeHtml(href) + "\">";
                    open.push("a");
                } else {
                    open.push("a-plain");
                }
            } else {
                out += closeElement(open, open.lastIndexOf("a") > open.lastIndexOf("a-plain") ? "a" : "a-plain");
            }
            break;
        case "br":
            out += "<br>";
            break;
        case "img":
            if (!closing) out += plain(attribute(attrs, "alt") ?? "");
            break;
        case "script":
        case "style":
            if (!closing && m[4] !== "/") skipUntil = name;
            break;
        default:
            // Recognised but not allowed: the tag goes, its text stays.
            break;
        }
    }

    if (skipUntil === null) out += plain(source.slice(last));
    while (open.length > 0) out += closeTag(open.pop());
    return out;
}

function closeTag(name) {
    if (name === "a-plain") return "";
    return "</" + name + ">";
}

// Closes `name` and anything opened inside it, then reopens those, so
// misnested input like <b><i>x</b>y</i> still yields balanced output.
function closeElement(open, name) {
    const at = open.lastIndexOf(name);
    if (at < 0) return "";
    const inner = open.splice(at);
    let out = "";
    for (let i = inner.length - 1; i >= 0; i--) out += closeTag(inner[i]);
    for (let i = 1; i < inner.length; i++) {
        // A rejected link stays rejected; a real link is not reopened, since
        // its href is gone and an empty anchor would be a dead link.
        if (inner[i] === "a" || inner[i] === "a-plain") continue;
        out += "<" + inner[i] + ">";
        open.push(inner[i]);
    }
    return out;
}

function relativeTime(then, now) {
    const minutes = Math.floor(Math.max(0, now - then) / 60000);
    if (minutes < 1) return "now";
    if (minutes < 60) return minutes + "m ago";
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return hours + "h ago";
    return Math.floor(hours / 24) + "d ago";
}
