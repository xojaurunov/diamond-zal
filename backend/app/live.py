"""Jonli yangilanish: Postgres `NOTIFY qobil` -> WebSocket orqali ulangan ilovalarga to'plam nomi.

Tinglash alohida oqimda (sinxron psycopg) — Windows'dagi asyncio ProactorEventLoop'da psycopg'ning
asinxron ulanishi ishlamaydi. Oqim xabarni ilovaning event loop'iga uzatadi."""

import asyncio
import threading

import psycopg

# jadval -> ilovadagi Firestore to'plam nomi (ilova o'sha nomdagi so'rovlarini qayta oladi)
COLLECTION = {'user_days': 'days', 'chat_messages': 'messages'}


class Hub:
    def __init__(self):
        self.clients = set()

    async def broadcast(self, collection):
        for ws in list(self.clients):
            try:
                await ws.send_json({'c': collection})
            except Exception:  # uzilgan ulanish
                self.clients.discard(ws)


class Listener:
    """`LISTEN qobil` — alohida oqimda; to'xtatish: stop()."""

    def __init__(self, info, hub, loop):
        self.info, self.hub, self.loop = info, hub, loop
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self._run, name='qobil-listen', daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.stopped.set()
        self.thread.join(timeout=3)

    def _run(self):
        while not self.stopped.is_set():
            try:
                with psycopg.connect(self.info, autocommit=True) as conn:
                    conn.execute('listen qobil')
                    while not self.stopped.is_set():
                        for n in conn.notifies(timeout=0.5):
                            name = COLLECTION.get(n.payload, n.payload)
                            asyncio.run_coroutine_threadsafe(self.hub.broadcast(name), self.loop)
            except psycopg.OperationalError:
                # baza qayta ishga tushsa — bir oz kutib qayta ulanadi
                self.stopped.wait(2)
