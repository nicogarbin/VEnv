"""Seed di dati Temperatura su Firestore.

Genera un punto ogni 30 minuti per il 22/01/2026 e lo salva nella collection
`Temperatura` (campi: `data`, `valore`, più metadata utili per debug).

Prerequisiti (UNO dei due):
- (Consigliato) Imposta GOOGLE_APPLICATION_CREDENTIALS al path del service account JSON
  scaricato da Firebase/Google Cloud.
- Oppure usa Application Default Credentials (es. `gcloud auth application-default login`).

Esecuzione (da questa cartella):
  python seed_temperature_2026_01_22.py

Opzioni utili:
  python seed_temperature_2026_01_22.py --dry-run
  python seed_temperature_2026_01_22.py --date 2026-01-22 --tz Europe/Rome
"""

from __future__ import annotations

import argparse
import math
import os
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Iterable

import firebase_admin
from firebase_admin import credentials, firestore


@dataclass(frozen=True)
class TempPoint:
    dt: datetime
    value_c: float


def _get_tzinfo(tz_name: str):
    """Ritorna tzinfo per nome timezone.

    Usa zoneinfo (py>=3.9). Se non disponibile, ritorna None (naive).
    """

    try:
        from zoneinfo import ZoneInfo  # type: ignore

        return ZoneInfo(tz_name)
    except Exception:
        return None


def _iter_half_hour_points(day: datetime, tz_name: str) -> Iterable[TempPoint]:
    tzinfo = _get_tzinfo(tz_name)

    start = datetime(day.year, day.month, day.day, 0, 0, 0, tzinfo=tzinfo)
    end = datetime(day.year, day.month, day.day, 23, 30, 0, tzinfo=tzinfo)

    # Andamento “realistico”: sinusoide giornaliera + piccola variazione.
    # Min ~ 7°C, max ~ 14°C circa.
    base = 10.5
    amp = 3.5

    t = start
    i = 0
    while t <= end:
        # fase: 0..2pi in 24h
        phase = (2.0 * math.pi) * (i / 48.0)
        value = base + amp * math.sin(phase - math.pi / 2)  # minimo di notte
        # micro-variazione deterministica (niente random)
        value += 0.3 * math.sin(phase * 3)
        yield TempPoint(dt=t, value_c=round(value, 2))

        t = t + timedelta(minutes=30)
        i += 1


def _init_firebase_app() -> None:
    if firebase_admin._apps:
        return

    # 1) Se c'è un service account JSON esplicito, usalo.
    sa_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if sa_path and os.path.exists(sa_path):
        cred = credentials.Certificate(sa_path)
        firebase_admin.initialize_app(cred)
        return

    # 2) Altrimenti prova ADC.
    cred = credentials.ApplicationDefault()
    firebase_admin.initialize_app(cred)


def _commit_in_batches(col_ref, docs: list[dict], batch_size: int = 450) -> int:
    # Firestore batch limit: 500 operazioni.
    # 450 per stare larghi.
    written = 0
    for i in range(0, len(docs), batch_size):
        chunk = docs[i : i + batch_size]
        batch = col_ref._client.batch()  # type: ignore[attr-defined]
        for doc in chunk:
            doc_ref = col_ref.document()  # auto-id
            batch.set(doc_ref, doc)
        batch.commit()
        written += len(chunk)
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed Temperatura su Firestore")
    parser.add_argument(
        "--date",
        default="2026-01-22",
        help="Data da generare in formato YYYY-MM-DD (default: 2026-01-22)",
    )
    parser.add_argument(
        "--tz",
        default="Europe/Rome",
        help="Timezone IANA (default: Europe/Rome)",
    )
    parser.add_argument(
        "--collection",
        default="Temperatura",
        help="Nome collection Firestore (default: Temperatura)",
    )
    parser.add_argument(
        "--database",
        default="default",
        help="Database Firestore (default: default)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Non scrive nulla, stampa solo cosa farebbe",
    )

    args = parser.parse_args()

    day = datetime.fromisoformat(args.date)

    points = list(_iter_half_hour_points(day, args.tz))

    if args.dry_run:
        print(f"[DRY-RUN] Generati {len(points)} punti per {args.date} ({args.tz}).")
        print("Esempio primi 5:")
        for p in points[:5]:
            print(f"  {p.dt.isoformat()} -> {p.value_c}°C")
        return 0

    _init_firebase_app()
    db = firestore.client(database_id=args.database)
    col_ref = db.collection(args.collection)

    docs: list[dict] = []
    for p in points:
        # Coerente con i tuoi Cloud Functions: `data` come stringa ISO.
        docs.append(
            {
                "data": p.dt.isoformat(),
                "valore": p.value_c,
                "source": "seed",
                "seed_date": args.date,
                "tz": args.tz,
                "createdAt": firestore.SERVER_TIMESTAMP,
            }
        )

    written = _commit_in_batches(col_ref, docs)
    print(f"Inseriti {written} documenti in '{args.collection}' per {args.date}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
