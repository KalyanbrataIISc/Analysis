"""Hardware-friendly CCA used by ``RT_acquisition_CCA.m``.

The MATLAB acquisition code does not call a general CCA routine.  It forms a
regularised CCA matrix and estimates its largest eigenvalue with eight power
iterations.  The functions below deliberately retain those choices so an
offline score has the same meaning as the online ``score_17``/``score_19``.

Arrays use the Python convention ``(samples, channels)``.  No amplitude-unit
conversion is necessary: CCA is invariant to a common scalar applied to the
EEG channels.
"""

from __future__ import annotations

from collections.abc import Iterable

import numpy as np
from numpy.typing import ArrayLike, NDArray


FloatArray = NDArray[np.float64]


def precompute_reference_terms(
    frequency_hz: float,
    n_samples: int,
    sampling_rate_hz: float,
    n_harmonics: int = 1,
) -> tuple[FloatArray, FloatArray]:
    """Return the sinusoidal reference and regularised inverse covariance.

    This is a line-for-line mathematical translation of MATLAB's
    ``precompute_reference_terms`` local function.
    """
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
    covariance = reference.T @ reference
    covariance_inverse = np.linalg.inv(
        covariance + 1e-8 * np.eye(covariance.shape[0])
    )
    return reference, covariance_inverse


def hw_friendly_cca_score(
    eeg: ArrayLike,
    reference: ArrayLike,
    reference_covariance_inverse: ArrayLike,
    n_power_iterations: int = 8,
) -> float:
    """Calculate one raw hardware-friendly CCA score.

    Parameters match MATLAB's ``hw_friendly_cca_score``.  ``eeg`` must already
    contain the samples to be scored (after any acquisition-like differencing
    and re-referencing).  The returned score is *not* a neurofeedback value or
    a difference between frequencies.
    """
    x = np.asarray(eeg, dtype=np.float64)
    y = np.asarray(reference, dtype=np.float64)
    cyy_inverse = np.asarray(reference_covariance_inverse, dtype=np.float64)

    if x.ndim != 2 or y.ndim != 2:
        raise ValueError("eeg and reference must both be two-dimensional")
    if x.shape[0] != y.shape[0]:
        raise ValueError("eeg and reference must have the same sample count")
    if x.shape[1] < 1 or not np.isfinite(x).all():
        raise ValueError("eeg must contain finite values and at least one channel")
    if cyy_inverse.shape != (y.shape[1], y.shape[1]):
        raise ValueError("reference_covariance_inverse has an incompatible shape")
    if n_power_iterations < 1:
        raise ValueError("n_power_iterations must be at least one")

    x = x - x.mean(axis=0, keepdims=True)
    cxx = x.T @ x
    cxy = x.T @ y
    cxx_inverse = np.linalg.inv(cxx + 1e-6 * np.eye(cxx.shape[0]))
    cca_matrix = cxx_inverse @ cxy @ cyy_inverse @ cxy.T

    vector = np.ones(cca_matrix.shape[0], dtype=np.float64)
    vector /= np.sqrt(cca_matrix.shape[0])
    for _ in range(n_power_iterations):
        vector = cca_matrix @ vector
        norm = np.linalg.norm(vector)
        if norm < 1e-12:
            return 0.0
        vector /= norm

    eigenvalue = float(vector.T @ cca_matrix @ vector)
    return float(np.sqrt(max(eigenvalue, 0.0)))


def acquisition_preprocess(
    ring_buffer: ArrayLike,
    sampling_rate_hz: float,
    *,
    demean_rereference: bool = True,
    z_score: bool = False,
    score_channel_indices: ArrayLike | None = None,
) -> FloatArray:
    """Reproduce the preprocessing inside ``RT_acquisition_CCA.m``.

    The input must hold one second plus ``round(fs / 50)`` samples.  As in the
    MATLAB ring buffer, delayed subtraction leaves exactly one second of data.
    Common-average re-referencing is performed across all supplied channels.
    ``score_channel_indices`` is applied *after* that operation, matching the
    MATLAB order (reference all acquired channels, then select ``pnqAllS``).
    """
    data = np.asarray(ring_buffer, dtype=np.float64)
    if data.ndim != 2:
        raise ValueError("ring_buffer must have shape (samples, channels)")
    if sampling_rate_hz <= 0:
        raise ValueError("sampling_rate_hz must be positive")
    if not np.isfinite(data).all():
        raise ValueError("ring_buffer contains NaN or infinite values")

    delay = int(round(sampling_rate_hz / 50.0))
    expected_samples = int(round(sampling_rate_hz)) + delay
    if data.shape[0] != expected_samples:
        raise ValueError(
            f"expected {expected_samples} samples (one second + delay), "
            f"received {data.shape[0]}"
        )

    filtered = data[delay:] - data[:-delay]
    if demean_rereference:
        filtered -= filtered.mean(axis=1, keepdims=True)
    if score_channel_indices is not None:
        indices = np.asarray(score_channel_indices)
        if indices.ndim != 1:
            raise ValueError("score_channel_indices must be one-dimensional")
        filtered = filtered[:, indices]
    if z_score:
        means = filtered.mean(axis=0, keepdims=True)
        standard_deviations = filtered.std(axis=0, ddof=1, keepdims=True)
        filtered = np.divide(
            filtered - means,
            standard_deviations,
            out=np.zeros_like(filtered),
            where=standard_deviations > 0,
        )
    return filtered


def rolling_cca_scores(
    eeg: ArrayLike,
    sampling_rate_hz: float,
    frequencies_hz: Iterable[float] = (17.0, 19.0),
    *,
    step_seconds: float = 0.1,
    n_harmonics: int = 1,
    n_power_iterations: int = 8,
    demean_rereference: bool = True,
    z_score: bool = False,
    score_channel_indices: ArrayLike | None = None,
) -> tuple[FloatArray, FloatArray]:
    """Return acquisition-like rolling raw CCA scores.

    Each row of ``scores`` is evaluated on a one-second block produced from a
    one-second-plus-delay ring buffer.  ``times_seconds`` gives the window-end
    time relative to row zero of ``eeg``; this mirrors the causal online score.
    """
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
        precompute_reference_terms(
            frequency, n_samples, sampling_rate_hz, n_harmonics
        )
        for frequency in frequencies
    ]
    window_stops = np.arange(
        ring_samples, data.shape[0] + 1, step_samples, dtype=np.int64
    )
    scores = np.empty((len(window_stops), len(frequencies)), dtype=np.float64)

    for row, stop in enumerate(window_stops):
        window = acquisition_preprocess(
            data[stop - ring_samples : stop],
            sampling_rate_hz,
            demean_rereference=demean_rereference,
            z_score=z_score,
            score_channel_indices=score_channel_indices,
        )
        for column, (reference, cyy_inverse) in enumerate(references):
            scores[row, column] = hw_friendly_cca_score(
                window,
                reference,
                cyy_inverse,
                n_power_iterations=n_power_iterations,
            )

    times_seconds = (window_stops - 1) / float(sampling_rate_hz)
    return times_seconds, scores


__all__ = [
    "acquisition_preprocess",
    "hw_friendly_cca_score",
    "precompute_reference_terms",
    "rolling_cca_scores",
]
