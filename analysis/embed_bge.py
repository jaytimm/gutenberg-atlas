"""Embed each book's body view with a BGE encoder.

Reads a CSV of pg_id and body_text, splits each text into chunks of about
350 words (inside BGE's 512-token window), embeds the chunks, and averages
them into one unit-length vector per book. Books already present in the
output file are skipped, so the output acts as a cache.
"""

import argparse
import csv
import sys

import numpy as np
import torch
from sentence_transformers import SentenceTransformer


def chunks_of(text, size):
    words = text.split()
    parts = [words[i:i + size] for i in range(0, len(words), size)]
    if len(parts) > 1 and len(parts[-1]) < size // 3:
        parts = parts[:-1]
    return [" ".join(p) for p in parts]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("views")
    parser.add_argument("out")
    parser.add_argument("--model", default="BAAI/bge-base-en-v1.5")
    parser.add_argument("--chunk-words", type=int, default=350)
    parser.add_argument("--batch-books", type=int, default=32)
    args = parser.parse_args()
    csv.field_size_limit(sys.maxsize)

    done = set()
    try:
        with open(args.out, newline="") as f:
            reader = csv.reader(f)
            next(reader)
            done = {row[0] for row in reader}
    except FileNotFoundError:
        pass

    with open(args.views, newline="", encoding="utf-8") as f:
        todo = [(r["pg_id"], r["body_text"]) for r in csv.DictReader(f)
                if r["pg_id"] not in done and r["body_text"]]
    print(f"{len(done)} cached, {len(todo)} to embed", file=sys.stderr)
    if not todo:
        return

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = SentenceTransformer(args.model, device=device)
    model.max_seq_length = 512
    if device == "cuda":
        model.half()
    dim = model.get_embedding_dimension()

    new_file = not done
    with open(args.out, "a", newline="") as f:
        writer = csv.writer(f)
        if new_file:
            writer.writerow(["pg_id"] + [f"e{i + 1}" for i in range(dim)])
        for start in range(0, len(todo), args.batch_books):
            batch = todo[start:start + args.batch_books]
            pieces = [chunks_of(text, args.chunk_words) for _, text in batch]
            flat = [c for p in pieces for c in p]
            vectors = model.encode(flat, batch_size=64, normalize_embeddings=True,
                                   convert_to_numpy=True).astype(np.float64)
            at = 0
            for (pg_id, _), p in zip(batch, pieces):
                mean = vectors[at:at + len(p)].mean(axis=0)
                at += len(p)
                mean /= np.linalg.norm(mean)
                writer.writerow([pg_id] + [f"{x:.6f}" for x in mean])
            f.flush()
            print(f"embedded {min(start + len(batch), len(todo))} of {len(todo)}",
                  file=sys.stderr)


if __name__ == "__main__":
    main()
