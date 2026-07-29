# ADR-002: Python trains, Java serves via ONNX

**Status:** Accepted
**Date:** 2026-07-29
**Author(s):** @bereket-7

## Context

The Fraud Engine needs to score every payment transaction in real time with a sub-200ms hard deadline. The model itself must be trained on historical labeled transaction data, tuned experimentally, and re-trained periodically.

Two concerns pull in different directions:

1. **Training** favours Python: scikit-learn, XGBoost, pandas, Jupyter notebooks, and the ML ecosystem live there.
2. **Serving** favours the JVM: the rest of the platform is Spring Boot / Java 17; adding a Python process on the critical synchronous path introduces a separate runtime, a process boundary, and an additional failure mode.

## Options considered

### Option A — Python for both training and serving (e.g. FastAPI)
Deploy a Python microservice that loads the model and exposes a scoring endpoint.

- ✅ Single language for the full ML lifecycle
- ❌ Adds a second runtime (Python + JVM) on the synchronous critical path
- ❌ Python inference latency is less predictable under GIL contention with concurrent requests
- ❌ Requires operating a Python service in Kubernetes alongside the Java services

### Option B — Retrain in Python, export to ONNX, serve via ONNX Runtime in Java (chosen)
The training pipeline (`payguard-fraud-model-training`) produces an ONNX artifact stored in S3. The Fraud Engine (`payguard-fraud-engine`) loads it via the ONNX Runtime Java binding.

- ✅ Training uses the full Python ML ecosystem with no constraints
- ✅ Serving runs inside the existing JVM process — no extra network hop, no extra container
- ✅ ONNX Runtime's Java API provides deterministic, low-latency inference suitable for a 200ms budget
- ✅ Model versioning is explicit: every ONNX artifact is tagged; the Fraud Engine records which version scored each transaction
- ❌ The training pipeline must export to ONNX — not all model types export cleanly (validated: XGBoost → ONNX via `skl2onnx` is well-supported)
- ❌ Model hot-reload requires a deploy or a version-switch mechanism in the Fraud Engine

### Option C — Pre-compute scores offline, store in Redis
Run scoring asynchronously; real-time path does a cache lookup.

- ✅ Microsecond lookup latency
- ❌ Stale scores for new or unseen merchants / devices
- ❌ Not viable for first-time transactions where no pre-computed score exists

## Decision

**Option B** — Python trains, ONNX Runtime serves inside the Java Fraud Engine.

The boundary between experimentation (Python) and production serving (JVM) is cleanly defined by the ONNX artifact in S3. This eliminates the Python runtime from the critical synchronous path while preserving complete freedom in the training pipeline.

## Consequences

- `payguard-fraud-model-training` must export every production model to ONNX format using `skl2onnx` before publishing to the S3 model registry.
- `payguard-fraud-engine` depends on `com.microsoft.onnxruntime:onnxruntime` as a Maven dependency.
- Each inference call tags its response with the model version it used — this is required for audit and rollback.
- The Fraud Engine must implement a rule-based fallback (`RulesFallbackEngine`) for cases where the ONNX model fails to load or exceeds the inference time budget. This is non-negotiable given the 200ms SLA.
- Model evaluation metrics (precision, recall, F1 on holdout set) must be recorded in `payguard-fraud-model-training/src/training/evaluate.py` before any artifact is promoted to the S3 registry.
