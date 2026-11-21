# -*- coding: utf-8 -*-
"""
FastDrop для Windows 7 (32 бит).

Работает по тому же протоколу, что и приложение FastDrop на телефонах и Linux:
  TCP 14680 - передача файлов, UDP 14681 - поиск устройств в сети.
Python 3.8 + tkinter, собирается в один .exe (см. .github/workflows/build-windows7.yml).
"""
import json
import os
import queue
import re
import socket
import subprocess
import sys
import threading
import time
import traceback

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox
except Exception:  # запуск без экрана (проверка сети)
    tk = None

APP_VERSION = '1.2'
TRANSFER_PORT = 14680
DISCOVERY_PORT = 14681
CHUNK = 1024 * 1024
BEACON_PREFIX = 'FASTDROP_READY|'

BG = '#000000'
CARD = '#0a110b'
EDGE = '#2b4f33'
ACCENT = '#4df56b'
TEXT = '#ffffff'
SUBTLE = '#9aa89e'
DANGER = '#ff6b7a'


# ───────────────────────── Вспомогательное ─────────────────────────

def app_dir():
    base = os.environ.get('APPDATA') or os.path.expanduser('~')
    d = os.path.join(base, 'FastDrop')
    try:
        os.makedirs(d)
    except OSError:
        pass
    return d


def load_settings():
    try:
        with open(os.path.join(app_dir(), 'settings.json'), 'r', encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_settings(data):
    try:
        with open(os.path.join(app_dir(), 'settings.json'), 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)
    except Exception:
        pass


def default_save_dir():
    return os.path.join(os.path.expanduser('~'), 'Downloads', 'FastDrop')


def fmt_size(n):
    if n <= 0:
        return '0 Б'
    units = ['Б', 'КБ', 'МБ', 'ГБ']
    v = float(n)
    i = 0
    while v >= 1024 and i < len(units) - 1:
        v /= 1024.0
        i += 1
    return ('%.2f %s' if i >= 2 else '%.0f %s') % (v, units[i])


def fmt_eta(remaining, speed):
    if speed <= 0.05 or remaining <= 0:
        return '--:--'
    sec = int(round(remaining / (speed * 1048576.0)))
    return '%02d:%02d' % (sec // 60, sec % 60)


def sanitize_rel(raw):
    parts = raw.replace('\\', '/').split('/')
    clean = []
    for p in parts:
        if not p or p in ('.', '..'):
            continue
        clean.append(re.sub(r'[:*?"<>|]', '_', p))
    return '/'.join(clean) if clean else 'received_file'


def local_ips():
    ips = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith('127.') and not ip.startswith('169.254.'):
                ips.append(ip)
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('10.255.255.255', 1))
        ip = s.getsockname()[0]
        s.close()
        if ip not in ips and not ip.startswith('127.'):
            ips.insert(0, ip)
    except Exception:
        pass
    return ips


class Cancelled(Exception):
    pass


class Stats(object):
    """Статистика скорости передачи, МБ/с."""

    def __init__(self):
        self.bytes = 0
        self.seconds = 0.0
        self.max = 0.0
        self.min = None

    def record(self, nbytes, seconds):
        if seconds <= 0:
            return
        self.bytes += nbytes
        self.seconds += seconds
        if seconds >= 0.15:
            sp = nbytes / 1048576.0 / seconds
            if sp > self.max:
                self.max = sp
            if self.min is None or sp < self.min:
                self.min = sp

    def avg(self):
        if self.seconds <= 0:
            return None
        return self.bytes / 1048576.0 / self.seconds

    def line(self):
        def f(v):
            return '—' if v is None else '%.1f' % v
        a = self.avg()
        if a is None:
            return ''
        return 'МБ/с: средняя %s · макс %s · мин %s' % (
            f(a), f(self.max if self.max > 0 else None), f(self.min))


# ───────────────────────── Сеть ─────────────────────────

class Net(object):
    def __init__(self, emit, get_name, get_save_dir):
        self.emit = emit
        self.get_name = get_name
        self.get_save_dir = get_save_dir
        self.cancel = threading.Event()
        self.running = True
        self.listening = False
        self.listen_error = None
        self.receiving = False
        self.busy = False
        self.server = None
        self.my_ips = []
        self.peers = {}
        self.peer_lock = threading.Lock()
        self.active = set()
        self.active_lock = threading.Lock()

    # --- запуск / остановка ---

    def start(self):
        self.my_ips = local_ips()
        self.start_server()
        threading.Thread(target=self._udp_listen, daemon=True).start()
        threading.Thread(target=self._beacon_loop, daemon=True).start()
        threading.Thread(target=self._ip_refresh_loop, daemon=True).start()

    def stop(self):
        self.running = False
        self.stop_server()
        self.close_active()

    def start_server(self):
        if self.listening:
            return
        try:
            srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            if os.name != 'nt':
                srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind(('', TRANSFER_PORT))
            srv.listen(8)
            self.server = srv
            self.listening = True
            self.listen_error = None
            threading.Thread(target=self._accept_loop, args=(srv,), daemon=True).start()
        except Exception as e:
            self.listening = False
            self.listen_error = str(e)
        self.emit('listen')

    def stop_server(self):
        srv = self.server
        self.server = None
        self.listening = False
        if srv is not None:
            try:
                srv.close()
            except Exception:
                pass
        self.emit('listen')

    def _accept_loop(self, srv):
        while self.running and srv is self.server:
            try:
                conn, addr = srv.accept()
            except Exception:
                break
            threading.Thread(target=self._handle_client, args=(conn, addr), daemon=True).start()

    def _ip_refresh_loop(self):
        while self.running:
            time.sleep(10)
            ips = local_ips()
            if ips != self.my_ips:
                self.my_ips = ips
                self.emit('listen')

    def close_active(self):
        with self.active_lock:
            socks = list(self.active)
        for s in socks:
            try:
                s.close()
            except Exception:
                pass

    def request_cancel(self):
        self.cancel.set()
        self.close_active()

    # --- поиск устройств ---

    def get_peers(self):
        with self.peer_lock:
            return sorted([(ip, v[0], v[1]) for ip, v in self.peers.items()])

    def _udp_listen(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.bind(('', DISCOVERY_PORT))
            s.settimeout(1.0)
        except Exception:
            return
        while self.running:
            changed = False
            try:
                data, addr = s.recvfrom(2048)
                msg = data.decode('utf-8', 'replace').strip()
                ip = addr[0]
                if msg.startswith(BEACON_PREFIX) and ip not in self.my_ips:
                    parts = msg[len(BEACON_PREFIX):].split('|')
                    os_name = parts[0].strip() or 'Device'
                    if len(parts) > 1 and parts[1].strip():
                        name = parts[1].strip()
                    else:
                        name = os_name
                    with self.peer_lock:
                        changed = ip not in self.peers or self.peers[ip][:2] != (os_name, name)
                        self.peers[ip] = (os_name, name, time.time())
            except socket.timeout:
                pass
            except Exception:
                if not self.running:
                    break
            now = time.time()
            with self.peer_lock:
                old = [k for k, v in self.peers.items() if now - v[2] > 5]
                for k in old:
                    del self.peers[k]
                    changed = True
            if changed:
                self.emit('peers')
        try:
            s.close()
        except Exception:
            pass

    def _beacon_loop(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        except Exception:
            pass
        while self.running:
            if self.listening:
                name = self.get_name().replace('|', ' ')
                payload = (BEACON_PREFIX + 'Windows|' + name).encode('utf-8')
                targets = set(['255.255.255.255'])
                for ip in self.my_ips:
                    p = ip.split('.')
                    if len(p) == 4:
                        targets.add('%s.%s.%s.255' % (p[0], p[1], p[2]))
                for t in targets:
                    try:
                        sock.sendto(payload, (t, DISCOVERY_PORT))
                    except Exception:
                        pass
            time.sleep(1.0)

    # --- приём ---

    def _handle_client(self, conn, addr):
        sender_ip = addr[0]
        f = None
        path = None
        received = 0
        total = 0
        stats = Stats()
        started = False
        with self.active_lock:
            self.active.add(conn)
        try:
            conn.settimeout(30)
            try:
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except Exception:
                pass

            buf = b''
            while b'\n' not in buf:
                chunk = conn.recv(65536)
                if not chunk:
                    return  # пустое подключение
                buf += chunk
                if len(buf) > 16384:
                    raise ValueError('Некорректный заголовок')
            line, rest = buf.split(b'\n', 1)
            header = line.decode('utf-8', 'replace').strip()
            sep = header.rfind('|')
            if sep <= 0:
                raise ValueError('Некорректный заголовок')
            rel = sanitize_rel(header[:sep])
            try:
                total = int(header[sep + 1:].strip())
            except ValueError:
                total = 0

            save_dir = self.get_save_dir()
            path = os.path.join(save_dir, *rel.split('/'))
            parent = os.path.dirname(path)
            if parent and not os.path.isdir(parent):
                os.makedirs(parent)

            self.cancel.clear()
            f = open(path, 'wb')
            conn.sendall(b'0\n')
            started = True
            self.receiving = True
            self.emit('recv_start', name=rel, total=total)

            last = time.time()
            interval = 0
            pending = rest
            while True:
                if self.cancel.is_set():
                    raise Cancelled()
                data = pending if pending else conn.recv(262144)
                pending = b''
                if not data:
                    break
                f.write(data)
                received += len(data)
                interval += len(data)
                now = time.time()
                el = now - last
                done = bool(total) and received >= total
                if el >= 0.2 or done:
                    stats.record(interval, el)
                    speed = (interval / 1048576.0 / el) if el > 0 else 0.0
                    self.emit('progress', name=rel, done=received, total=total,
                              speed=speed, eta=fmt_eta(total - received, speed))
                    interval = 0
                    last = now
                if done:
                    break

            f.close()
            f = None
            if total > 0 and received < total:
                raise ValueError('Соединение прервано (%d из %d байт)' % (received, total))
            self.emit('recv_done', path=path, name=rel, size=received or total,
                      sender=sender_ip, stats=stats.line())
        except Cancelled:
            self._drop_partial(f, path)
            f = None
            if started:
                self.emit('cancelled')
        except Exception as e:
            self._drop_partial(f, path)
            f = None
            if started:
                if self.cancel.is_set():
                    self.emit('cancelled')
                else:
                    self.emit('error', text='Ошибка приёма: %s' % e)
        finally:
            if f is not None:
                try:
                    f.close()
                except Exception:
                    pass
            with self.active_lock:
                self.active.discard(conn)
            try:
                conn.close()
            except Exception:
                pass
            self.receiving = False

    def _drop_partial(self, f, path):
        try:
            if f is not None:
                f.close()
        except Exception:
            pass
        try:
            if path and os.path.exists(path):
                os.remove(path)
        except Exception:
            pass

    # --- отправка ---

    def send_worker(self, host, items):
        self.busy = True
        self.cancel.clear()
        stats = Stats()
        n = len(items)
        done = 0
        self.emit('send_start', count=n)
        try:
            for i, it in enumerate(items):
                if self.cancel.is_set():
                    raise Cancelled()
                self.emit('send_file', index=i + 1, count=n,
                          name=it.get('title') or it['rel'], size=it['size'])
                self._send_one(host, it, stats)
                done += 1
            self.emit('send_done', count=done, stats=stats.line())
        except Cancelled:
            self.emit('cancelled')
        except Exception as e:
            if self.cancel.is_set():
                self.emit('cancelled')
            else:
                self.emit('error', text='Ошибка отправки: %s' % e)
        finally:
            self.busy = False

    def _send_one(self, host, it, stats):
        size = it['size']
        name = it.get('title') or it['rel']
        s = socket.create_connection((host, TRANSFER_PORT), timeout=6)
        with self.active_lock:
            self.active.add(s)
        try:
            s.settimeout(30)
            try:
                s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except Exception:
                pass
            s.sendall(('%s|%d\n' % (it['rel'], size)).encode('utf-8'))

            buf = b''
            while b'\n' not in buf:
                c = s.recv(64)
                if not c:
                    raise Exception('Получатель закрыл соединение')
                buf += c
            try:
                offset = int(buf.split(b'\n', 1)[0].strip() or 0)
            except ValueError:
                offset = 0
            offset = max(0, min(offset, size))

            sent = offset
            interval = 0
            last = time.time()

            if it.get('data') is not None:
                s.sendall(it['data'][offset:])
                sent = size
                self.emit('progress', name=name, done=sent, total=size, speed=0.0, eta='00:00')
            else:
                with open(it['path'], 'rb') as f:
                    f.seek(offset)
                    while sent < size:
                        if self.cancel.is_set():
                            raise Cancelled()
                        chunk = f.read(min(CHUNK, size - sent))
                        if not chunk:
                            break
                        s.sendall(chunk)
                        sent += len(chunk)
                        interval += len(chunk)
                        now = time.time()
                        el = now - last
                        if el >= 0.2 or sent >= size:
                            stats.record(interval, el)
                            speed = (interval / 1048576.0 / el) if el > 0 else 0.0
                            self.emit('progress', name=name, done=sent, total=size,
                                      speed=speed, eta=fmt_eta(size - sent, speed))
                            interval = 0
                            last = now
                if sent < size:
                    raise Exception('Файл изменился во время отправки')

            # Ждём, пока получатель дочитает и закроет соединение.
            try:
                s.shutdown(socket.SHUT_WR)
            except Exception:
                pass
            s.settimeout(20)
            try:
                while s.recv(1024):
                    pass
            except Exception:
                pass
        finally:
            with self.active_lock:
                self.active.discard(s)
            try:
                s.close()
            except Exception:
                pass


# ───────────────────────── Интерфейс ─────────────────────────

def mix(c1, c2, t):
    """Смешивает два цвета #rrggbb: t=0 -> c1, t=1 -> c2."""
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    r = [int(a[i] + (b[i] - a[i]) * t) for i in range(3)]
    return '#%02x%02x%02x' % tuple(r)


if tk is not None:

    class PillButton(tk.Canvas):
        def __init__(self, master, text, command, width=120, height=38, kind='normal', bg=BG):
            tk.Canvas.__init__(self, master, width=width, height=height, bg=bg,
                               highlightthickness=0, bd=0)
            self.w = width
            self.h = height
            self.text = text
            self.command = command
            self.kind = kind
            self.enabled = True
            self.hover = False
            self.bind('<Enter>', lambda e: self._set_hover(True))
            self.bind('<Leave>', lambda e: self._set_hover(False))
            self.bind('<ButtonRelease-1>', self._click)
            self._draw()

        def _round(self, x1, y1, x2, y2, r, **kw):
            pts = [x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r, x2, y2 - r, x2, y2,
                   x2 - r, y2, x1 + r, y2, x1, y2, x1, y2 - r, x1, y1 + r, x1, y1]
            return self.create_polygon(pts, smooth=True, **kw)

        def _draw(self):
            self.delete('all')
            if self.kind == 'accent':
                fill, outline, fg = '#14401c', ACCENT, ACCENT
            elif self.kind == 'danger':
                fill, outline, fg = '#3a1218', DANGER, DANGER
            else:
                fill, outline, fg = '#0f1a11', EDGE, TEXT
            if self.hover and self.enabled:
                fill = mix(fill, '#ffffff', 0.10)
            if not self.enabled:
                fg = SUBTLE
            self._round(2, 2, self.w - 2, self.h - 2, self.h // 2, fill=fill,
                        outline=outline, width=1.5)
            self.create_text(self.w // 2, self.h // 2, text=self.text, fill=fg,
                             font=('Segoe UI', 10, 'bold'))

        def _set_hover(self, v):
            self.hover = v
            self._draw()

        def _click(self, event):
            if not self.enabled:
                return
            if 0 <= event.x <= self.w and 0 <= event.y <= self.h:
                self.command()

        def set_text(self, text):
            self.text = text
            self._draw()

        def set_enabled(self, v):
            self.enabled = v
            self._draw()

    class Radar(tk.Canvas):
        COLORS = {
            'waiting': ACCENT,
            'receiving': '#b8ff7a',
            'sending': ACCENT,
            'off': SUBTLE,
            'error': DANGER,
        }

        def __init__(self, master, w=300, h=190):
            tk.Canvas.__init__(self, master, width=w, height=h, bg=CARD,
                               highlightthickness=0, bd=0)
            self.w = w
            self.h = h
            self.state = 'waiting'

        def tick(self):
            self.delete('all')
            cx, cy = self.w / 2.0, self.h / 2.0
            color = self.COLORS.get(self.state, ACCENT)
            if self.state in ('waiting', 'receiving', 'sending'):
                speed = 1 if self.state == 'waiting' else 2
                t = (time.time() / 3.0) % 1.0
                for i in range(3):
                    ph = (t * speed + i / 3.0) % 1.0
                    r = 42 + (self.h / 2.0 - 44) * ph
                    fade = 1.0 - ph
                    self.create_oval(cx - r, cy - r, cx + r, cy + r,
                                     outline=mix(CARD, color, 0.75 * fade), width=2)
            else:
                r = 58
                self.create_oval(cx - r, cy - r, cx + r, cy + r,
                                 outline=mix(CARD, color, 0.3), width=2)
            self.create_oval(cx - 36, cy - 36, cx + 36, cy + 36,
                             fill=mix(CARD, color, 0.18), outline=color, width=2)
            # значок компьютера
            self.create_rectangle(cx - 17, cy - 14, cx + 17, cy + 8, outline=color, width=2)
            self.create_line(cx, cy + 8, cx, cy + 14, fill=color, width=2)
            self.create_line(cx - 9, cy + 15, cx + 9, cy + 15, fill=color, width=2)

    class App(object):
        def __init__(self):
            self.settings = load_settings()
            self.events = queue.Queue()
            self.net = Net(self._emit, self.get_name, self.get_save_dir)
            self.mode = 'idle'
            self.last_path = None
            self.last_folder = None
            self.peer_ips = []
            self.dots_text = ''
            self.progress = 0.0

            self.root = tk.Tk()
            self.root.title('FastDrop')
            self.root.configure(bg=BG)
            self.root.geometry('480x860')
            self.root.minsize(440, 700)
            self.root.protocol('WM_DELETE_WINDOW', self.on_close)
            self._build()

            self.net.start()
            self._refresh_hero()
            self.root.after(80, self._pump)
            self.root.after(70, self._anim)

        # --- настройки ---

        def get_name(self):
            name = (self.settings.get('device_name') or '').strip()
            if name:
                return name
            try:
                return socket.gethostname() or 'Windows'
            except Exception:
                return 'Windows'

        def get_save_dir(self):
            d = (self.settings.get('save_dir') or '').strip()
            return d or default_save_dir()

        def _emit(self, kind, **data):
            self.events.put((kind, data))

        # --- построение окна ---

        def _label(self, parent, text='', fg=TEXT, size=10, bold=False, bg=CARD, mono=False):
            font = ('Consolas' if mono else 'Segoe UI', size, 'bold' if bold else 'normal')
            return tk.Label(parent, text=text, bg=bg, fg=fg, font=font)

        def _build(self):
            outer = tk.Frame(self.root, bg=BG)
            outer.pack(fill='both', expand=True, padx=16, pady=10)

            self._label(outer, 'FastDrop', TEXT, 16, True, BG).pack()
            self._label(outer, 'v' + APP_VERSION, SUBTLE, 8, False, BG).pack()

            hero = tk.Frame(outer, bg=CARD, highlightbackground=EDGE, highlightthickness=1)
            hero.pack(fill='x', pady=(8, 8))
            self.radar = Radar(hero)
            self.radar.pack(pady=(6, 0))
            self.radar.bind('<Button-1>', lambda e: self._toggle_receive())
            self.name_lbl = self._label(hero, self.get_name(), TEXT, 18, True)
            self.name_lbl.pack()
            self.status_lbl = self._label(hero, '', ACCENT, 11, True)
            self.status_lbl.pack(pady=(4, 0))
            self.hint_lbl = self._label(hero, '', SUBTLE, 9)
            self.hint_lbl.pack()
            self.ip_lbl = self._label(hero, '', SUBTLE, 10, False, CARD, True)
            self.ip_lbl.configure(cursor='hand2')
            self.ip_lbl.pack(pady=(6, 10))
            self.ip_lbl.bind('<Button-1>', self._copy_ip)

            self._label(outer, 'НАЙДЕНЫ', SUBTLE, 8, True, BG).pack(anchor='w')
            self.peer_list = tk.Listbox(
                outer, height=3, bg=CARD, fg=TEXT, selectbackground='#14401c',
                selectforeground=ACCENT, highlightbackground=EDGE, highlightcolor=ACCENT,
                highlightthickness=1, relief='flat', bd=0, font=('Segoe UI', 10),
                activestyle='none', exportselection=False)
            self.peer_list.pack(fill='x', pady=(2, 8))
            self.peer_list.bind('<<ListboxSelect>>', self._pick_peer)

            self._label(outer, 'IP ПОЛУЧАТЕЛЯ', SUBTLE, 8, True, BG).pack(anchor='w')
            self.ip_var = tk.StringVar(value=self.settings.get('last_ip', ''))
            self.ip_entry = tk.Entry(
                outer, textvariable=self.ip_var, bg=CARD, fg=TEXT, insertbackground=ACCENT,
                relief='flat', bd=0, highlightbackground=EDGE, highlightcolor=ACCENT,
                highlightthickness=1, font=('Consolas', 12))
            self.ip_entry.pack(fill='x', pady=(2, 10), ipady=6)

            row = tk.Frame(outer, bg=BG)
            row.pack(pady=(0, 10))
            self.btn_files = PillButton(row, 'Файлы', self._send_files, 126)
            self.btn_files.pack(side='left', padx=4)
            self.btn_folder = PillButton(row, 'Папка', self._send_folder, 126)
            self.btn_folder.pack(side='left', padx=4)
            self.btn_text = PillButton(row, 'Текст', self._send_text, 126)
            self.btn_text.pack(side='left', padx=4)

            card = tk.Frame(outer, bg=CARD, highlightbackground=EDGE, highlightthickness=1)
            card.pack(fill='x')
            top = tk.Frame(card, bg=CARD)
            top.pack(fill='x', padx=14, pady=(10, 0))
            self.speed_lbl = self._label(top, '0.0 МБ/с', ACCENT, 16, True)
            self.speed_lbl.pack(side='left')
            self.eta_lbl = self._label(top, '--:--', SUBTLE, 11, False, CARD, True)
            self.eta_lbl.pack(side='right')
            self.bar = tk.Canvas(card, height=10, bg=CARD, highlightthickness=0, bd=0)
            self.bar.pack(fill='x', padx=14, pady=8)
            self.bar.bind('<Configure>', lambda e: self._draw_bar())
            info = tk.Frame(card, bg=CARD)
            info.pack(fill='x', padx=14)
            self.pct_lbl = self._label(info, '0.0%', TEXT, 9)
            self.pct_lbl.pack(side='left')
            self.size_lbl = self._label(info, '0 Б / 0 Б', SUBTLE, 9, False, CARD, True)
            self.size_lbl.pack(side='right')
            self.file_lbl = self._label(card, '', SUBTLE, 9)
            self.file_lbl.configure(wraplength=400, justify='left', anchor='w')
            self.file_lbl.pack(fill='x', padx=14, pady=(6, 0))
            self.msg_lbl = self._label(card, 'Готово', TEXT, 9)
            self.msg_lbl.configure(wraplength=400, justify='left', anchor='w')
            self.msg_lbl.pack(fill='x', padx=14, pady=(2, 0))
            self.stats_lbl = self._label(card, '', SUBTLE, 9, False, CARD, True)
            self.stats_lbl.configure(wraplength=400, justify='left', anchor='w')
            self.stats_lbl.pack(fill='x', padx=14, pady=(2, 0))

            self.actions = tk.Frame(card, bg=CARD)
            self.actions.pack(pady=(8, 10))
            self.btn_open_file = PillButton(self.actions, 'Открыть файл', self._open_file,
                                            140, 34, 'accent', CARD)
            self.btn_open_folder = PillButton(self.actions, 'Открыть папку', self._open_folder,
                                              140, 34, 'normal', CARD)
            self.btn_cancel = PillButton(self.actions, 'Отмена', self._cancel,
                                         140, 34, 'danger', CARD)

            foot = tk.Frame(outer, bg=BG)
            foot.pack(pady=(10, 0))
            self.btn_name = PillButton(foot, 'Название', self._rename, 110, 32)
            self.btn_name.pack(side='left', padx=3)
            self.btn_dir = PillButton(foot, 'Папка приёма', self._pick_save_dir, 130, 32)
            self.btn_dir.pack(side='left', padx=3)
            self.btn_toggle = PillButton(foot, 'Выкл. приём', self._toggle_receive, 120, 32)
            self.btn_toggle.pack(side='left', padx=3)

        # --- обновление экрана ---

        def _draw_bar(self):
            self.bar.delete('all')
            w = max(self.bar.winfo_width(), 20)
            h = 10
            self.bar.create_rectangle(0, 0, w, h, fill=mix(CARD, '#ffffff', 0.12), outline='')
            fw = int(w * max(0.0, min(1.0, self.progress)))
            if fw > 0:
                color = DANGER if self.msg_lbl.cget('fg') == DANGER else ACCENT
                self.bar.create_rectangle(0, 0, fw, h, fill=color, outline='')

        def _set_progress(self, done, total, speed=None, eta=None):
            self.progress = (float(done) / total) if total > 0 else 0.0
            self.pct_lbl.configure(text='%.1f%%' % (self.progress * 100))
            self.size_lbl.configure(text='%s / %s' % (fmt_size(done), fmt_size(total)))
            if speed is not None:
                self.speed_lbl.configure(text='%.1f МБ/с' % speed)
            if eta is not None:
                self.eta_lbl.configure(text=eta)
            self._draw_bar()

        def _set_msg(self, text, error=False):
            self.msg_lbl.configure(text=text, fg=DANGER if error else TEXT)

        def _show_actions(self, file_btn, folder_btn, cancel_btn):
            for b in (self.btn_open_file, self.btn_open_folder, self.btn_cancel):
                b.pack_forget()
            if file_btn:
                self.btn_open_file.pack(side='left', padx=4)
            if folder_btn:
                self.btn_open_folder.pack(side='left', padx=4)
            if cancel_btn:
                self.btn_cancel.pack(side='left', padx=4)

        def _refresh_hero(self):
            net = self.net
            if self.mode == 'receiving':
                state, status, hint = 'receiving', 'Идёт приём файла', 'Не закрывайте приложение'
            elif self.mode == 'sending':
                state, status, hint = 'sending', 'Идёт отправка', 'Не закрывайте приложение'
            elif net.listening:
                state, status, hint = 'waiting', 'Ожидание отправителя', 'Другие устройства видят вас в сети'
            elif net.listen_error:
                state, status, hint = 'error', 'Не удалось включить приём', 'Нажмите, чтобы повторить'
            else:
                state, status, hint = 'off', 'Приём выключен', 'Нажмите, чтобы включить'
            self.radar.state = state
            self.status_base = status
            self.status_lbl.configure(
                text=status, fg=Radar.COLORS.get(state, ACCENT))
            self.hint_lbl.configure(text=hint)
            self.name_lbl.configure(text=self.get_name())
            self.ip_lbl.configure(text='   '.join(net.my_ips))
            self.btn_toggle.set_text('Выкл. приём' if net.listening else 'Вкл. приём')
            busy = self.mode != 'idle'
            for b in (self.btn_files, self.btn_folder, self.btn_text):
                b.set_enabled(not busy)

        def _anim(self):
            try:
                self.radar.tick()
                if self.radar.state == 'waiting':
                    n = 1 + int(time.time() * 1.2) % 3
                    text = 'Ожидание отправителя' + '.' * n
                    if text != self.dots_text:
                        self.dots_text = text
                        self.status_lbl.configure(text=text)
            except Exception:
                pass
            self.root.after(70, self._anim)

        def _refresh_peers(self):
            peers = self.net.get_peers()
            self.peer_list.delete(0, 'end')
            self.peer_ips = []
            for ip, os_name, name in peers:
                self.peer_list.insert('end', '%s   %s   (%s)' % (name, ip, os_name))
                self.peer_ips.append(ip)
            if peers and not self.ip_var.get().strip():
                self.ip_var.set(peers[0][0])

        def _pump(self):
            try:
                while True:
                    kind, d = self.events.get_nowait()
                    self._handle(kind, d)
            except queue.Empty:
                pass
            except Exception:
                try:
                    with open(os.path.join(app_dir(), 'error.log'), 'a', encoding='utf-8') as f:
                        f.write(traceback.format_exc())
                except Exception:
                    pass
            self.root.after(80, self._pump)

        def _handle(self, kind, d):
            if kind in ('listen',):
                self._refresh_hero()
            elif kind == 'peers':
                self._refresh_peers()
            elif kind == 'recv_start':
                self.mode = 'receiving'
                self.last_path = None
                self.last_folder = None
                self.file_lbl.configure(text=d['name'])
                self._set_progress(0, d['total'], 0.0, '--:--')
                self._set_msg('Приём: %s' % d['name'])
                self.stats_lbl.configure(text='')
                self._show_actions(False, False, True)
                self._refresh_hero()
            elif kind == 'progress':
                self.file_lbl.configure(text=d['name'])
                self._set_progress(d['done'], d['total'], d['speed'], d['eta'])
            elif kind == 'recv_done':
                self.mode = 'idle'
                self.last_path = d['path']
                self.last_folder = os.path.dirname(d['path'])
                self._set_progress(d['size'], d['size'], 0.0, '00:00')
                self._set_msg('Файл принят · сохранено в папку %s' % os.path.basename(self.get_save_dir()))
                self.stats_lbl.configure(text=d.get('stats', ''))
                self._show_actions(True, True, False)
                self._refresh_hero()
                self._maybe_show_text(d)
            elif kind == 'send_start':
                self.mode = 'sending'
                self.stats_lbl.configure(text='')
                self._set_progress(0, 0, 0.0, '--:--')
                self._set_msg('Подключение...')
                self._show_actions(False, False, True)
                self._refresh_hero()
            elif kind == 'send_file':
                self.file_lbl.configure(text=d['name'])
                self._set_progress(0, d['size'], 0.0, '--:--')
                self._set_msg('Отправка (%d/%d)' % (d['index'], d['count']))
            elif kind == 'send_done':
                self.mode = 'idle'
                self.speed_lbl.configure(text='0.0 МБ/с')
                self.eta_lbl.configure(text='00:00')
                self.progress = 1.0
                self._draw_bar()
                self._set_msg('Отправлено' if d['count'] == 1 else 'Отправлено элементов: %d' % d['count'])
                self.stats_lbl.configure(text=d.get('stats', ''))
                self._show_actions(False, False, False)
                self._refresh_hero()
            elif kind == 'cancelled':
                self.mode = 'idle'
                self.speed_lbl.configure(text='0.0 МБ/с')
                self._set_msg('Передача отменена')
                self._show_actions(False, False, False)
                self._refresh_hero()
            elif kind == 'error':
                self.mode = 'idle'
                self.speed_lbl.configure(text='0.0 МБ/с')
                self._set_msg(d['text'], True)
                self._show_actions(False, False, False)
                self._refresh_hero()
                self._draw_bar()

        # --- действия ---

        def _copy_ip(self, event=None):
            ips = self.net.my_ips
            if ips:
                self.root.clipboard_clear()
                self.root.clipboard_append(ips[0])
                self._set_msg('Скопировано: %s' % ips[0])

        def _pick_peer(self, event=None):
            sel = self.peer_list.curselection()
            if sel and sel[0] < len(self.peer_ips):
                self.ip_var.set(self.peer_ips[sel[0]])

        def _toggle_receive(self):
            if self.mode != 'idle':
                return
            if self.net.listening:
                self.net.stop_server()
            else:
                self.net.start_server()
            self._refresh_hero()

        def _rename(self):
            win = tk.Toplevel(self.root)
            win.title('Название устройства')
            win.configure(bg=BG)
            win.geometry('360x130')
            win.transient(self.root)
            win.grab_set()
            self._label(win, 'Так вас видят другие устройства:', SUBTLE, 9, False, BG).pack(pady=(14, 4))
            var = tk.StringVar(value=self.settings.get('device_name', '') or self.get_name())
            e = tk.Entry(win, textvariable=var, bg=CARD, fg=TEXT, insertbackground=ACCENT,
                         relief='flat', highlightbackground=EDGE, highlightcolor=ACCENT,
                         highlightthickness=1, font=('Segoe UI', 11))
            e.pack(fill='x', padx=20, ipady=5)
            e.focus_set()

            def ok():
                v = var.get().strip()[:24]
                self.settings['device_name'] = v
                save_settings(self.settings)
                win.destroy()
                self._refresh_hero()

            PillButton(win, 'Сохранить', ok, 130, 34, 'accent').pack(pady=12)

        def _pick_save_dir(self):
            d = filedialog.askdirectory(title='Папка для принятых файлов',
                                        initialdir=self.get_save_dir() if os.path.isdir(self.get_save_dir()) else None)
            if d:
                self.settings['save_dir'] = d
                save_settings(self.settings)
                self._set_msg('Папка приёма: %s' % d)

        def _ready_to_send(self):
            if self.mode != 'idle':
                return None
            host = self.ip_var.get().strip()
            if not host:
                messagebox.showinfo('FastDrop', 'Укажите IP получателя')
                return None
            return host

        def _start_send(self, host, items):
            if not items:
                return
            self.settings['last_ip'] = host
            save_settings(self.settings)
            self.mode = 'sending'
            self._refresh_hero()
            threading.Thread(target=self.net.send_worker, args=(host, items), daemon=True).start()

        def _send_files(self):
            host = self._ready_to_send()
            if not host:
                return
            paths = filedialog.askopenfilenames(title='Выберите файлы')
            items = []
            for p in paths:
                try:
                    items.append({'rel': os.path.basename(p), 'size': os.path.getsize(p), 'path': p})
                except OSError:
                    pass
            self._start_send(host, items)

        def _send_folder(self):
            host = self._ready_to_send()
            if not host:
                return
            root_dir = filedialog.askdirectory(title='Выберите папку')
            if not root_dir:
                return
            root_dir = os.path.normpath(root_dir)
            folder = os.path.basename(root_dir) or 'folder'
            items = []
            for cur, dirs, files in os.walk(root_dir):
                for fn in files:
                    full = os.path.join(cur, fn)
                    rel = os.path.relpath(full, root_dir).replace('\\', '/')
                    try:
                        items.append({'rel': folder + '/' + rel, 'size': os.path.getsize(full), 'path': full})
                    except OSError:
                        pass
            if not items:
                self._set_msg('Выбранная папка пуста')
                return
            self._start_send(host, items)

        def _send_text(self):
            host = self._ready_to_send()
            if not host:
                return
            win = tk.Toplevel(self.root)
            win.title('Отправить текст')
            win.configure(bg=BG)
            win.geometry('420x320')
            win.transient(self.root)
            win.grab_set()
            txt = tk.Text(win, bg=CARD, fg=TEXT, insertbackground=ACCENT, relief='flat',
                          highlightbackground=EDGE, highlightcolor=ACCENT, highlightthickness=1,
                          font=('Segoe UI', 11), wrap='word')
            txt.pack(fill='both', expand=True, padx=14, pady=(14, 8))
            txt.focus_set()

            def paste():
                try:
                    txt.insert('end', self.root.clipboard_get())
                except tk.TclError:
                    pass

            def send():
                content = txt.get('1.0', 'end').strip()
                if not content:
                    return
                data = content.encode('utf-8')
                item = {'rel': '%d_message.txt' % int(time.time() * 1000), 'size': len(data),
                        'data': data, 'title': 'Текст'}
                win.destroy()
                self._start_send(host, [item])

            row = tk.Frame(win, bg=BG)
            row.pack(pady=(0, 12))
            PillButton(row, 'Вставить', paste, 130, 34).pack(side='left', padx=4)
            PillButton(row, 'Отправить', send, 130, 34, 'accent').pack(side='left', padx=4)

        def _cancel(self):
            self.net.request_cancel()

        def _open_file(self):
            if self.last_path and os.path.exists(self.last_path):
                self._startfile(self.last_path)

        def _open_folder(self):
            folder = self.last_folder or self.get_save_dir()
            if os.path.isdir(folder):
                self._startfile(folder)

        def _startfile(self, path):
            try:
                if hasattr(os, 'startfile'):
                    os.startfile(path)
                else:
                    subprocess.Popen(['xdg-open', path])
            except Exception as e:
                messagebox.showerror('FastDrop', 'Не удалось открыть: %s' % e)

        def _maybe_show_text(self, d):
            if not d['name'].lower().endswith('.txt') or d['size'] > 1024 * 1024:
                return
            try:
                with open(d['path'], 'r', encoding='utf-8', errors='replace') as f:
                    content = f.read()
            except Exception:
                return
            if not content.strip():
                return
            win = tk.Toplevel(self.root)
            win.title('Сообщение от %s' % d.get('sender', ''))
            win.configure(bg=BG)
            win.geometry('420x320')
            txt = tk.Text(win, bg=CARD, fg=TEXT, relief='flat', highlightbackground=EDGE,
                          highlightthickness=1, font=('Segoe UI', 11), wrap='word')
            txt.insert('1.0', content)
            txt.pack(fill='both', expand=True, padx=14, pady=(14, 8))

            def copy():
                self.root.clipboard_clear()
                self.root.clipboard_append(content)

            row = tk.Frame(win, bg=BG)
            row.pack(pady=(0, 12))
            PillButton(row, 'Копировать', copy, 130, 34, 'accent').pack(side='left', padx=4)
            PillButton(row, 'Закрыть', win.destroy, 130, 34).pack(side='left', padx=4)

        def on_close(self):
            self.net.stop()
            self.root.destroy()

        def run(self):
            self.root.mainloop()


def main():
    if tk is None:
        print('tkinter не найден')
        return
    App().run()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        try:
            with open(os.path.join(app_dir(), 'error.log'), 'a', encoding='utf-8') as f:
                f.write(traceback.format_exc())
        except Exception:
            pass
        raise