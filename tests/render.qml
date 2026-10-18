import QtQuick
import Quickshell
import Quickshell.Io

// Offscreen render harness, run by tests/render.sh as the shell.qml of a
// scratch copy of the sources. It hosts the real BannerStack (and through it
// the real Store and NotificationServer) in a plain window over a smooth
// wallpaper, and takes commands over Quickshell IPC: screenshots, state
// dumps, and the calls a click would make. Hover and the compositor's blur
// cannot be produced offscreen, and the offscreen platform only gets Qt's
// software renderer, which draws no shader effects: no shadows, no rounded
// photo corners. tests/isolated.sh covers those on a real compositor.
ShellRoot {
    id: root

    property string outDir: Quickshell.env("MNOTIF_RENDER_OUT") || "/tmp"

    function banners(): var {
        const found = [];
        for (let i = 0; i < stack.children.length; i++) {
            const c = stack.children[i];
            if (c.key !== undefined && c.presence !== undefined) found.push(c);
        }
        return found;
    }

    function bannerFor(id: int): var {
        return root.banners().find(b => b.key === id) ?? null;
    }

    FloatingWindow {
        implicitWidth: 760
        implicitHeight: 600
        color: "black"

        Item {
            id: canvas

            anchors.fill: parent

            // A smooth wallpaper: blurring it would change nothing, so the
            // translucent cards look roughly as they would over real blur.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.dark ? "#3a2d5c" : "#9cc8f2" }
                    GradientStop { position: 0.55; color: Theme.dark ? "#1b2440" : "#3d86d9" }
                    GradientStop { position: 1.0; color: Theme.dark ? "#0b0f1c" : "#1a4fa8" }
                }
            }

            BannerStack {
                id: stack

                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: Theme.alignRight ? parent.right : undefined
                anchors.left: Theme.alignRight ? undefined : parent.left
                width: Theme.surfaceWidth
            }
        }
    }

    IpcHandler {
        target: "test"

        function shot(name: string): string {
            const path = root.outDir + "/" + name + ".png";
            const requested = Date.now();
            canvas.grabToImage(result => {
                const ok = result.saveToFile(path);
                console.info("render: shot " + name + " after " + (Date.now() - requested) + " ms" + (ok ? "" : " FAILED"));
            });
            return path;
        }

        // One line per banner, top to bottom on screen.
        function state(): string {
            const list = root.banners().sort((a, b) => a.y - b.y);
            return JSON.stringify({
                "banners": list.map(b => ({
                    "id": b.key,
                    "title": b.title,
                    "image": b.content.image,
                    "appIcon": b.content.appIcon,
                    "y": Math.round(b.y),
                    "height": Math.round(b.height),
                    "presence": Math.round(b.presence * 100) / 100,
                    "leaving": b.leaving,
                    "chrome": b.chromeShown,
                    "timeout": b.timeout,
                    "countdown": b.placed && !b.leaving && b.timeout > 0
                })),
                "queued": Store.queue.length,
                "occupied": Store.occupied,
                "menuOpen": stack.menu.open,
                "menuRows": stack.menu.entries.map(e => e.label)
            });
        }

        function activate(id: int): string {
            const b = root.bannerFor(id);
            if (!b) return "no banner " + id;
            b.activate();
            return "ok";
        }

        function dismiss(id: int): string {
            const b = root.bannerFor(id);
            if (!b) return "no banner " + id;
            b.dismiss();
            return "ok";
        }

        function toggleMenu(id: int): string {
            const b = root.bannerFor(id);
            if (!b) return "no banner " + id;
            b.toggleMenu();
            return "ok";
        }

        function choose(index: int): string {
            const entry = stack.menu.entries[index];
            if (!entry) return "no row " + index;
            stack.menu.choose(entry);
            return "ok";
        }
    }
}
