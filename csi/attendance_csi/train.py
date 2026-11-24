"""Select window size and model from labelled recordings, evaluate, and save (Steps 13-15).

    python -m attendance_csi.train --data data/recordings --out models/presence.joblib \
        --windows 2,3,5 --step 1

Evaluation uses StratifiedGroupKFold grouped by *recording*, so overlapping
windows from one recording never appear in both train and test folds (which
would inflate accuracy). Every candidate (threshold baseline, logistic
regression, random forest, SVM) x window size is scored on out-of-fold
predictions; the best by F1 (ties: lower false-positive rate) is refit on all
data and saved together with its window parameters and evaluation report.
"""
import argparse
import json
import sys
import time
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_score, recall_score
from sklearn.model_selection import StratifiedGroupKFold

from .features import MODEL_FEATURES, windows
from .io import load_directory
from .models import candidates


def build_dataset(recordings, window_s, step_s):
    rows = []
    for stem, meta, frames in recordings:
        for start, end, feats in windows(frames, window_s, step_s):
            rows.append(dict(feats, recording=stem, label=int(meta['label'] == 'occupied'),
                             occupancy=meta.get('occupancy'), activity=meta.get('activity', ''),
                             experiment=meta.get('experiment'), start=start))
    return pd.DataFrame(rows)


def metrics(y, pred):
    tn, fp, fn, tp = confusion_matrix(y, pred, labels=[0, 1]).ravel()
    return {
        'accuracy': accuracy_score(y, pred),
        'precision': precision_score(y, pred, zero_division=0),
        'recall': recall_score(y, pred, zero_division=0),
        'f1': f1_score(y, pred, zero_division=0),
        'false_positive_rate': fp / (fp + tn) if fp + tn else 0.0,
        'false_negative_rate': fn / (fn + tp) if fn + tp else 0.0,
        'confusion_matrix': {'tn': int(tn), 'fp': int(fp), 'fn': int(fn), 'tp': int(tp)},
        'windows': int(len(y)),
    }


def evaluate(df, make_model, splits):
    X, y, groups = df[MODEL_FEATURES].to_numpy(), df['label'].to_numpy(), df['recording'].to_numpy()
    pred = np.full(len(y), -1)
    for train, test in StratifiedGroupKFold(n_splits=splits, shuffle=True, random_state=0).split(X, y, groups):
        if len(set(y[train])) < 2:
            continue
        model = make_model().fit(X[train], y[train])
        pred[test] = (model.predict_proba(X[test])[:, 1] >= 0.5).astype(int)
    mask = pred >= 0
    return metrics(y[mask], pred[mask])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--data', default='data/recordings')
    parser.add_argument('--out', default='models/presence.joblib')
    parser.add_argument('--windows', default='2,3,5', help='Window lengths in seconds to compare')
    parser.add_argument('--step', type=float, default=1.0)
    parser.add_argument('--models', default='threshold,logistic_regression,random_forest,svm')
    parser.add_argument('--min-confidence', type=float, default=0.7,
                        help='Below this probability the live service reports UNKNOWN')
    args = parser.parse_args(argv)

    recordings = load_directory(args.data)
    per_class = {lab: sum(1 for _, m, _ in recordings if m['label'] == lab) for lab in ('empty', 'occupied')}
    print(f'Loaded {len(recordings)} recordings: {per_class}')
    if min(per_class.values()) < 2:
        print('Need at least 2 recordings of each class for grouped evaluation (5+ recommended).', file=sys.stderr)
        return 2
    splits = min(5, min(per_class.values()))
    pool = candidates(MODEL_FEATURES)
    chosen = [m for m in args.models.split(',') if m in pool]
    results = []
    for window_s in [float(w) for w in args.windows.split(',')]:
        df = build_dataset(recordings, window_s, args.step)
        if df.empty or df['label'].nunique() < 2:
            print(f'  window {window_s}s: not enough usable windows')
            continue
        for name in chosen:
            m = evaluate(df, pool[name], splits)
            results.append(dict(model=name, window_s=window_s, **m))
            print(f'  window {window_s:>4}s  {name:<20} F1={m["f1"]:.3f} acc={m["accuracy"]:.3f} '
                  f'FPR={m["false_positive_rate"]:.3f} FNR={m["false_negative_rate"]:.3f}')
    if not results:
        print('No candidate could be evaluated.', file=sys.stderr)
        return 2
    best = sorted(results, key=lambda r: (-r['f1'], r['false_positive_rate']))[0]
    df = build_dataset(recordings, best['window_s'], args.step)
    model = pool[best['model']]().fit(df[MODEL_FEATURES].to_numpy(), df['label'].to_numpy())
    rates = df['packet_rate']
    bundle = dict(model=model, kind=best['model'], features=MODEL_FEATURES, window_s=best['window_s'],
                  step_s=args.step, min_confidence=args.min_confidence,
                  # Windows with far fewer packets than training data are unreliable -> UNKNOWN.
                  min_packet_rate=float(rates.quantile(0.05) * 0.5), evaluation=best, all_results=results,
                  recordings=[s for s, _, _ in recordings], trained_at=time.time())
    if best['model'] == 'threshold':
        bundle['rule'] = model.describe()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, out)
    report = {k: v for k, v in bundle.items() if k != 'model'}
    out.with_suffix('.report.json').write_text(json.dumps(report, indent=2, default=float))
    print(f'\nSelected {best["model"]} with {best["window_s"]}s windows '
          f'(grouped out-of-fold F1 {best["f1"]:.3f}, FPR {best["false_positive_rate"]:.3f}).')
    print(f'Confusion matrix: {best["confusion_matrix"]}')
    print(f'Saved {out} and {out.with_suffix(".report.json")}')
    if best['f1'] < 0.9 or best['false_positive_rate'] > 0.05:
        print('WARNING: performance is below a safe level for attendance. Collect more varied data, '
              'review the ESP32 placement, and do not deploy until this improves.', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
