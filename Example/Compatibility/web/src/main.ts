import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import Underline from "@tiptap/extension-underline";
import Highlight from "@tiptap/extension-highlight";
import Link from "@tiptap/extension-link";
import TaskList from "@tiptap/extension-task-list";
import TaskItem from "@tiptap/extension-task-item";
import Collaboration from "@tiptap/extension-collaboration";
import CollaborationCursor from "@tiptap/extension-collaboration-cursor";
import { HocuspocusProvider } from "@hocuspocus/provider";
import * as Y from "yjs";

// Must match the native apps: document (room) name and the root fragment name
// YBinding encodes into (YBinding.defaultFragmentName == "prosemirror").
const DOCUMENT_NAME = "prosekit-compatibility";
const FRAGMENT_NAME = "prosemirror";

const NAMES = [
  "Ada", "Grace", "Alan", "Edsger", "Barbara", "Donald",
  "Margaret", "Dennis", "Radia", "Linus", "Katherine", "Bjarne",
];
const COLORS = [
  "#e11d48", "#ea580c", "#ca8a04", "#16a34a", "#0d9488",
  "#2563eb", "#7c3aed", "#c026d3",
];
const user = {
  name: `${NAMES[Math.floor(Math.random() * NAMES.length)]} (web)`,
  color: COLORS[Math.floor(Math.random() * COLORS.length)],
};

const ydoc = new Y.Doc();
const provider = new HocuspocusProvider({
  url: `ws://${location.host}/collaboration`,
  name: DOCUMENT_NAME,
  document: ydoc,
});

const editor = new Editor({
  element: document.querySelector("#editor")!,
  extensions: [
    // Mirror ProseKit's slice-1 schema: no code block / horizontal rule, and
    // history is delegated to Yjs (Collaboration brings its own undo).
    StarterKit.configure({
      history: false,
      codeBlock: false,
      horizontalRule: false,
    }),
    Underline,
    Highlight.configure({ multicolor: true }),
    Link.configure({ openOnClick: false }),
    TaskList,
    TaskItem.configure({ nested: true }),
    Collaboration.configure({ document: ydoc, field: FRAGMENT_NAME }),
    CollaborationCursor.configure({ provider, user }),
  ],
});

// --- Connection status -------------------------------------------------------

const statusEl = document.querySelector<HTMLElement>("#status")!;
provider.on("status", ({ status }: { status: string }) => {
  statusEl.dataset.state = status;
  statusEl.textContent = status;
});

// --- Participants bar --------------------------------------------------------
// CollaborationCursor already paints remote carets inside the editor; this bar
// additionally lists every awareness peer, so native peers that publish
// presence without a cursor are visible too.

const participantsEl = document.querySelector<HTMLElement>("#participants")!;
function renderParticipants() {
  const states = [...provider.awareness!.getStates().values()];
  participantsEl.replaceChildren(
    ...states
      .map((state) => state.user as { name?: string; color?: string } | undefined)
      .filter((u): u is { name: string; color: string } => Boolean(u?.name))
      .map((u) => {
        const chip = document.createElement("span");
        chip.className = "chip";
        chip.style.setProperty("--chip-color", u.color ?? "#888");
        chip.textContent = u.name;
        return chip;
      }),
  );
}
provider.awareness!.on("change", renderParticipants);
renderParticipants();

// --- Toolbar -----------------------------------------------------------------

type Button = {
  label: string;
  title: string;
  run: () => void;
  isActive?: () => boolean;
  isEnabled?: () => boolean;
};

const chain = () => editor.chain().focus();
const buttons: (Button | "divider")[] = [
  { label: "B", title: "Bold", run: () => chain().toggleBold().run(), isActive: () => editor.isActive("bold") },
  { label: "I", title: "Italic", run: () => chain().toggleItalic().run(), isActive: () => editor.isActive("italic") },
  { label: "U", title: "Underline", run: () => chain().toggleUnderline().run(), isActive: () => editor.isActive("underline") },
  { label: "S", title: "Strike", run: () => chain().toggleStrike().run(), isActive: () => editor.isActive("strike") },
  { label: "</>", title: "Code", run: () => chain().toggleCode().run(), isActive: () => editor.isActive("code") },
  { label: "HL", title: "Highlight", run: () => chain().toggleHighlight({ color: "#fef08a" }).run(), isActive: () => editor.isActive("highlight") },
  "divider",
  { label: "H1", title: "Heading 1", run: () => chain().toggleHeading({ level: 1 }).run(), isActive: () => editor.isActive("heading", { level: 1 }) },
  { label: "H2", title: "Heading 2", run: () => chain().toggleHeading({ level: 2 }).run(), isActive: () => editor.isActive("heading", { level: 2 }) },
  { label: "H3", title: "Heading 3", run: () => chain().toggleHeading({ level: 3 }).run(), isActive: () => editor.isActive("heading", { level: 3 }) },
  "divider",
  { label: "•", title: "Bullet list", run: () => chain().toggleBulletList().run(), isActive: () => editor.isActive("bulletList") },
  { label: "1.", title: "Ordered list", run: () => chain().toggleOrderedList().run(), isActive: () => editor.isActive("orderedList") },
  { label: "☑", title: "Task list", run: () => chain().toggleTaskList().run(), isActive: () => editor.isActive("taskList") },
  { label: "❝", title: "Blockquote", run: () => chain().toggleBlockquote().run(), isActive: () => editor.isActive("blockquote") },
  "divider",
  { label: "↺", title: "Undo", run: () => chain().undo().run(), isEnabled: () => editor.can().undo() },
  { label: "↻", title: "Redo", run: () => chain().redo().run(), isEnabled: () => editor.can().redo() },
];

const toolbarEl = document.querySelector<HTMLElement>("#toolbar")!;
const refreshers: (() => void)[] = [];
for (const item of buttons) {
  if (item === "divider") {
    const div = document.createElement("span");
    div.className = "divider";
    toolbarEl.appendChild(div);
    continue;
  }
  const btn = document.createElement("button");
  btn.type = "button";
  btn.textContent = item.label;
  btn.title = item.title;
  btn.addEventListener("click", item.run);
  toolbarEl.appendChild(btn);
  refreshers.push(() => {
    btn.classList.toggle("active", item.isActive?.() ?? false);
    btn.disabled = item.isEnabled ? !item.isEnabled() : false;
  });
}
const refreshToolbar = () => refreshers.forEach((fn) => fn());
editor.on("transaction", refreshToolbar);
editor.on("selectionUpdate", refreshToolbar);
refreshToolbar();
