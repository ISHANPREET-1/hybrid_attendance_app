"""Candidate presence models. All expose fit / predict_proba like scikit-learn."""
import numpy as np
from sklearn.base import BaseEstimator, ClassifierMixin
from sklearn.calibration import CalibratedClassifierCV
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC


class ThresholdBaseline(BaseEstimator, ClassifierMixin):
    """Single-feature threshold (guide Step 15 baseline).

    Picks the feature, direction and threshold with the best balanced accuracy on
    the training windows only. Probability is a logistic of the scaled distance
    from the threshold, so confidence is low near the boundary.
    """

    def __init__(self, feature_names=None):
        self.feature_names = feature_names

    def fit(self, X, y):
        X, y = np.asarray(X, float), np.asarray(y, int)
        best = (-1.0, 0, 0.0, 1)
        for j in range(X.shape[1]):
            values = np.unique(X[:, j])
            candidates = (values[:-1] + values[1:]) / 2 if values.size > 1 else values
            if candidates.size > 200:
                candidates = np.quantile(X[:, j], np.linspace(0.01, 0.99, 200))
            for t in candidates:
                for sign in (1, -1):
                    pred = (sign * (X[:, j] - t) > 0).astype(int)
                    tpr = pred[y == 1].mean() if (y == 1).any() else 0
                    tnr = 1 - pred[y == 0].mean() if (y == 0).any() else 0
                    score = (tpr + tnr) / 2
                    if score > best[0]:
                        best = (score, j, float(t), sign)
        self.train_score_, self.feature_index_, self.threshold_, self.sign_ = best
        self.scale_ = float(np.std(X[:, self.feature_index_]) or 1.0)
        self.classes_ = np.array([0, 1])
        return self

    def predict_proba(self, X):
        x = np.asarray(X, float)[:, self.feature_index_]
        z = self.sign_ * (x - self.threshold_) / (0.25 * self.scale_)
        p = 1 / (1 + np.exp(-np.clip(z, -50, 50)))
        return np.column_stack([1 - p, p])

    def predict(self, X):
        return (self.predict_proba(X)[:, 1] >= 0.5).astype(int)

    def describe(self):
        name = self.feature_names[self.feature_index_] if self.feature_names else self.feature_index_
        return f'{name} {">" if self.sign_ > 0 else "<"} {self.threshold_:.5g}'


def candidates(feature_names):
    return {
        'threshold': lambda: ThresholdBaseline(feature_names),
        'logistic_regression': lambda: make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000, class_weight='balanced')),
        'random_forest': lambda: RandomForestClassifier(n_estimators=200, min_samples_leaf=3, class_weight='balanced', random_state=0),
        'svm': lambda: make_pipeline(StandardScaler(), CalibratedClassifierCV(SVC(class_weight='balanced', random_state=0), cv=3, ensemble=False)),
    }
