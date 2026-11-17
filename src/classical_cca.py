"""Classical CCA scores for the offline SSVEP analysis.

This module deliberately does not use the regularized covariance matrix or
power iteration from ``RT_acquisition_CCA.m``.  It computes the largest
ordinary sample canonical correlation using an SVD of whitened, centered EEG
and sinusoidal-reference matrices.  Acquisition-like delayed subtraction and
channel referencing are retained so the classical and hardware-friendly
notebooks differ only in their CCA estimator.
"""

from __future__ import annotations

from collections.abc import Iterable

import numpy as np
from numpy.typing import ArrayLike, NDArray

from cca import acquisition_preprocess


FloatArray = NDArray[np.float64]


def reference_signals(
    frequency_hz: float,
    n_samples: int,
    sampling_rate_hz: float,
    n_harmonics: int = 1,
) -> FloatArray:
    """Return centered sine/cosine reference columns for one frequency."""
    if frequency_hz <= 0 or sampling_rate_hz <= 0:
        raise ValueError("frequency_hz and sampling_rate_hz must be positive")
    if n_samples < 2 or n_harmonics < 1:
        raise ValueError("n_samples >= 2 and n_harmonics >= 1 are required")

    time = np.arange(n_samples, dtype=np.float64) / float(sampling_rate_hz)
    reference = np.empty((n_samples, 2 * n_harmonics), dtype=np.float64)
    for harmonic in range(1, n_harmonics + 1):
        phase = 2.0 * np.pi * frequency_hz * harmonic * time
        reference[:, 2 * harmonic - 2] = np.sin(phase)
        reference[:, 2 * harmonic - 1] = np.cos(phase)
    reference -= reference.mean(axis=0, keepdims=True)
    return reference


def _whiten_centered(data: FloatArray) -> FloatArray:
    """Whiten the non-null column space without covariance regularization."""
    gram = data.T @ data
    eigenvalues, eigenvectors = np.linalg.eigh(gram)
    largest = float(np.max(eigenvalues, initial=0.0))
    tolerance = max(data.shape) * np.finfo(np.float64).eps * largest
    keep = eigenvalues > tolerance
    if not np.any(keep):
        return np.empty((data.shape[0], 0), dtype=np.float64)
    return data @ (eigenvectors[:, keep] / np.sqrt(eigenvalues[keep]))


def classical_cca_score(eeg: ArrayLike, reference: ArrayLike) -> float:
    """Return the largest ordinary canonical correlation between two matrices."""
    x = np.asarray(eeg, dtype=np.float64)
    y = np.asarray(reference, dtype=np.float64)
    if x.ndim != 2 or y.ndim != 2:
        raise ValueError("eeg and reference must both be two-dimensional")
    if x.shape[0] != y.shape[0]:
        raise ValueError("eeg and reference must have the same sample count")
    if not np.isfinite(x).all() or not np.isfinite(y).all():
        raise ValueError("eeg and reference must contain only finite values")

    x = x - x.mean(axis=0, keepdims=True)
    y = y - y.mean(axis=0, keepdims=True)
    whitened_x = _whiten_centered(x)
    whitened_y = _whiten_centered(y)
    if whitened_x.shape[1] == 0 or whitened_y.shape[1] == 0:
        return 0.0

    singular_values = np.linalg.svd(
        whitened_x.T @ whitened_y, compute_uv=False
    )
    return float(np.clip(singular_values[0], 0.0, 1.0))


def rolling_classical_cca_scores(
    eeg: ArrayLike,
    sampling_rate_hz: float,
    frequencies_hz: Iterable[float] = (17.0, 19.0),
    *,
    step_seconds: float = 0.1,
    n_harmonics: int = 1,
    demean_rereference: bool = True,
    z_score: bool = False,
    score_channel_indices: ArrayLike | None = None,
) -> tuple[FloatArray, FloatArray]:
    """Return rolling one-second classical CCA scores at each frequency."""
    data = np.asarray(eeg, dtype=np.float64)
    frequencies = tuple(float(frequency) for frequency in frequencies_hz)
    if data.ndim != 2 or data.shape[1] < 1:
        raise ValueError("eeg must have shape (samples, channels)")
    if not frequencies:
        raise ValueError("at least one frequency is required")
    if step_seconds <= 0:
        raise ValueError("step_seconds must be positive")

    n_samples = int(round(sampling_rate_hz))
    delay = int(round(sampling_rate_hz / 50.0))
    ring_samples = n_samples + delay
    step_samples = max(1, int(round(step_seconds * sampling_rate_hz)))
    if data.shape[0] < ring_samples:
        return (
            np.empty(0, dtype=np.float64),
            np.empty((0, len(frequencies)), dtype=np.float64),
        )

    references = [
        reference_signals(frequency, n_samples, sampling_rate_hz, n_harmonics)
        for frequency in frequencies
    ]
    window_stops = np.arange(
        ring_samples, data.shape[0] + 1, step_samples, dtype=np.int64
    )
    scores = np.empty((len(window_stops), len(frequencies)), dtype=np.float64)
    for row, stop in enumerate(window_stops):
        window = acquisition_preprocess(
            data[stop-ring_samples:stop],
            sampling_rate_hz,
            demean_rereference=demean_rereference,
            z_score=z_score,
            score_channel_indices=score_channel_indices,
        )
        for column, reference in enumerate(references):
            scores[row, column] = classical_cca_score(window, reference)

    times_seconds = (window_stops - 1) / float(sampling_rate_hz)
    return times_seconds, scores


__all__ = [
    "classical_cca_score",
    "reference_signals",
    "rolling_classical_cca_scores",
]
