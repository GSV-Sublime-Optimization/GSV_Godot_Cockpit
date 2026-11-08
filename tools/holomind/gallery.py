r"""Mind View Gallery: one small window that tabs between every bakeoff entry and the colony's front ends.

- One tab per entry: what it is, its receipt screenshot, its measured costs, and buttons to run it on the
  shared fixture or live. Only one entry runs at a time: opening another closes the previous one.
- A "Colony tools" tab: every front end in dev's tools/colony/contracts/ports.v1.json, with its live state from
  the MSI's CHORUS feed when reachable, and an Open button where it can actually be opened from this rig.

Rules (bakeoff #14): an ordinary window, never topmost; Esc or the close button quits it and closes whatever it
launched. Entries open windowed. It reads; it never writes to any rig.

    python tools/holomind/gallery.py            # run from anywhere
"""
import json
import os
import pathlib
import platform
import subprocess
import sys
import tkinter as tk
import webbrowser
from tkinter import ttk

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import portable  # noqa: E402

WT = pathlib.Path(os.environ.get('BAKEOFF_WORKTREES', r'C:\dev\worktrees'))
GODOT = os.environ.get('GODOT', r'C:\dev\tools\godot\4.7.1\Godot_v4.7.1-stable_win64.exe' if os.name == 'nt' else 'godot')
PY = os.environ.get('PYTHON', sys.executable)
PORTS = pathlib.Path(os.environ.get('COLONY_PORTS', r'C:\dev\active\dev\tools\colony\contracts\ports.v1.json'))
HERE_RIG = portable.rig()   # COLONY_RIG overrides; MSI* = msi, *L9* = l9, else i3 (as before)

# Each entry: where it lives and how to run it. 'godot' entries run a scene from their own worktree.
ENTRIES = [
    {'id': 'holomind', 'title': 'HOLOMIND (i3 Claude, #15)', 'dir': 'cockpit-holomind', 'kind': 'godot',
     'scene': 'res://scenes/HoloMind.tscn', 'fixture_args': ['--fixture=res://tests/fixtures/holomind_shared_feed.json'],
     'live_args': ['--as=keath'], 'shot': 'receipts/holomind-shared-fixture.png',
     'blurb': 'A holographic table you look into, and the cockpit agents work in: shared channel with read receipts, '
              'work queue, Mind that answers, agents at work, copyable brief (C).'},
    {'id': 'chorus', 'title': 'CHORUS (MSI Claude, #16)', 'dir': 'bakeoff-pr16', 'kind': 'web',
     'shot': 'receipts/chorus-fixture-1600x900.png', 'msi_url': 'http://127.0.0.1:8767/',
     'blurb': 'The fleet as a night sky you can hear: breathing stars, comets for thoughts, a river of memory, '
              'an opt-in Cmaj7 chord. Browser tab.'},
    {'id': 'muse', 'title': 'Muse war room + Atlas (#17, #19)', 'dir': 'bakeoff-pr19', 'kind': 'godot',
     'scene': 'res://scenes/HoloRoom.tscn', 'fixture_args': [], 'live_args': [], 'shot': '',
     'blurb': 'A 3D war-room volume with holographic layers you pull up, a raymarched density slice, and a '
              'Capability Atlas layer of 75 graded entries.'},
    {'id': 'gpt6', 'title': 'Cognitive Loom (GPT-6, #18)', 'dir': 'bakeoff-pr18', 'kind': 'godot',
     'scene': 'res://scenes/PrimeMind.tscn', 'fixture_args': [], 'live_args': [], 'shot': '',
     'blurb': 'A thought tape you scrub like a DAW, with a causal inspector for each thought and three lenses.'},
]
EXTRA = pathlib.Path(__file__).with_name('gallery_entries.json')   # run commands learned from testing each entry
if EXTRA.exists():
    for e in json.loads(EXTRA.read_text(encoding='utf-8')):
        for x in ENTRIES:
            if x['id'] == e.get('id'):
                x.update(e)


class Gallery:
    def __init__(self, root: tk.Tk):
        self.root, self.child, self.images = root, None, {}
        root.title('Mind View Gallery: every entry, one window (Esc quits)')
        root.geometry('1100x760')
        root.configure(bg='#0b0f1a')
        root.bind('<Escape>', lambda _e: self.quit())
        root.protocol('WM_DELETE_WINDOW', self.quit)
        style = ttk.Style(root)
        style.theme_use('clam')
        style.configure('TNotebook', background='#0b0f1a', borderwidth=0)
        style.configure('TNotebook.Tab', background='#151c2e', foreground='#9fd8ff', padding=(14, 6))
        style.map('TNotebook.Tab', background=[('selected', '#24304d')], foreground=[('selected', '#ffd27a')])
        style.configure('TFrame', background='#0b0f1a')
        self.status = tk.StringVar(value='Pick a tab. Ctrl+1..9 switches tabs. Running: nothing.')
        nb = ttk.Notebook(root)
        nb.pack(fill='both', expand=True, padx=8, pady=8)
        self.nb = nb
        for e in ENTRIES:
            nb.add(self.entry_tab(nb, e), text=e['title'])
        nb.add(self.tools_tab(nb), text='Colony tools')
        for i in range(1, 10):
            root.bind(f'<Control-Key-{i}>', lambda _e, i=i: nb.select(min(i, len(nb.tabs())) - 1))
        tk.Label(root, textvariable=self.status, bg='#0b0f1a', fg='#7d8aa8', anchor='w').pack(fill='x', padx=10, pady=(0, 8))

    def label(self, parent, text, size=11, color='#d8e2ff', **kw):
        return tk.Label(parent, text=text, bg='#0b0f1a', fg=color, font=('Segoe UI', size), justify='left', **kw)

    def entry_tab(self, nb, e):
        f = ttk.Frame(nb)
        self.label(f, e['title'], 16, '#ffd27a').pack(anchor='w', padx=12, pady=(10, 2))
        self.label(f, e['blurb'], 11, wraplength=1040).pack(anchor='w', padx=12)
        if e.get('notes'):
            self.label(f, e['notes'], 10, '#9fd8ff', wraplength=1040).pack(anchor='w', padx=12, pady=(6, 0))
        bar = tk.Frame(f, bg='#0b0f1a')
        bar.pack(anchor='w', padx=12, pady=8)
        here = WT / e['dir']
        if e['kind'] == 'godot':
            tk.Button(bar, text='Run on the shared fixture', command=lambda: self.run(e, 'fixture')).pack(side='left', padx=(0, 8))
            tk.Button(bar, text='Run live', command=lambda: self.run(e, 'live')).pack(side='left', padx=(0, 8))
        else:
            tk.Button(bar, text='Open (fixture page)', command=lambda: self.open_web(e, 'fixture')).pack(side='left', padx=(0, 8))
            tk.Button(bar, text='Open live (on the MSI)', command=lambda: self.open_web(e, 'live')).pack(side='left', padx=(0, 8))
        tk.Button(bar, text='Close it', command=self.stop).pack(side='left')
        if not here.exists():
            self.label(bar, f'  (not checked out here: {here})', 10, '#f5b041').pack(side='left')
        shot = here / e['shot'] if e.get('shot') else None
        if shot and shot.exists():
            try:
                img = tk.PhotoImage(file=str(shot))
                factor = max(1, img.width() // 1040 + (1 if img.width() % 1040 else 0))
                img = img.subsample(factor, factor)
                self.images[e['id']] = img
                tk.Label(f, image=img, bg='#0b0f1a').pack(padx=12, pady=4)
            except tk.TclError:
                self.label(f, f'(could not show {shot.name})', 10, '#f5b041').pack(anchor='w', padx=12)
        else:
            self.label(f, '(no receipt screenshot yet)', 10, '#7d8aa8').pack(anchor='w', padx=12)
        return f

    def tools_tab(self, nb):
        f = ttk.Frame(nb)
        self.label(f, 'Colony front ends', 16, '#ffd27a').pack(anchor='w', padx=12, pady=(10, 2))
        self.label(f, f'From dev tools/colony/contracts/ports.v1.json; live state from the MSI spine (via CHORUS) when '
                      f'reachable. You are on the {HERE_RIG}: loopback-only services open only on their own rig.',
                   10, '#7d8aa8', wraplength=1040).pack(anchor='w', padx=12)
        cols = ('machine', 'port', 'name', 'state', 'opens here?')
        tv = ttk.Treeview(f, columns=cols, show='headings', height=22)
        for c, w in zip(cols, (80, 70, 260, 120, 360)):
            tv.heading(c, text=c)
            tv.column(c, width=w, anchor='w')
        tv.pack(fill='both', expand=True, padx=12, pady=8)
        state = self.spine_state()
        web_like = ('web', 'ui', 'dashboard', 'openhands', 'openwebui', 'serena', 'simulatedverse', 'forgejo', 'gateway',
                    'dev-mentor', 'chatdev', 'openclaw', 'culture', 'gordon', 'skyclaw', 'mempalace', 'icecast', 'omniroute', 'proxy')
        try:
            entries = json.loads(PORTS.read_text(encoding='utf-8'))['entries']
        except Exception:
            entries = []
        self.urls = {}
        for s in entries:
            name = str(s.get('name', ''))
            if not any(w in name for w in web_like):
                continue
            machine, port, bind = s.get('machine'), s.get('port'), str(s.get('bind', ''))
            here = machine == HERE_RIG or bind == '0.0.0.0'
            live = state.get(name.split('-')[0], state.get(name, ''))
            iid = tv.insert('', 'end', values=(machine, port, name, live or '?',
                                                 'yes' if here else f'only on the {machine} (bound to {bind})'))
            if here:
                host = '127.0.0.1' if machine == HERE_RIG else machine
                self.urls[iid] = f'http://{host}:{port}/'
        tv.bind('<Double-1>', lambda _e: self.open_url(tv))
        self.label(f, 'Double-click a row that opens here to open it in your browser.', 10, '#7d8aa8').pack(anchor='w', padx=12)
        return f

    def spine_state(self):
        try:
            sp = portable.chorus_feed(6).get('spine', {})
            return {s['name']: ('UP' if s.get('up') else 'DOWN') for s in sp.get('services', [])}
        except Exception:
            return {}

    def open_url(self, tv):
        sel = tv.selection()
        if sel and sel[0] in self.urls:
            webbrowser.open(self.urls[sel[0]])

    def run(self, e, mode):
        self.stop()
        args = [GODOT, '--path', str(WT / e['dir']), '--windowed', '--resolution', '1600x900', e['scene'], '--']
        args += e.get('fixture_args' if mode == 'fixture' else 'live_args', [])
        env = dict(os.environ, APPDATA=str(WT / '_appdata' / f"gallery-{e['id']}"))
        self.child = subprocess.Popen(args, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.status.set(f"Running: {e['title']} ({mode}). Esc in its window, or 'Close it' here, closes it.")

    def open_web(self, e, mode):
        if mode == 'live':
            if HERE_RIG != 'msi':
                self.status.set('CHORUS live is served on the MSI loopback only; open it from the MSI.')
                return
            webbrowser.open(e['msi_url'])
            return
        page = WT / e['dir'] / 'chorus' / 'index.html'
        webbrowser.open(page.as_uri() + '#fixture')
        self.status.set(f"Opened {e['title']} in your browser (fixture).")

    def stop(self):
        if self.child and self.child.poll() is None:
            self.child.terminate()
        self.child = None
        self.status.set('Running: nothing.')

    def quit(self):
        self.stop()
        self.root.destroy()


if __name__ == '__main__':
    root = tk.Tk()
    root.attributes('-topmost', False)
    Gallery(root)
    root.mainloop()
