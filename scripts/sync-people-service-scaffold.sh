#!/usr/bin/env bash
# Sync apps/people-service-scaffold from apps/people-service, preserving templated files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${REPO_ROOT}/apps/people-service"
TARGET="${REPO_ROOT}/apps/people-service-scaffold"

rsync -a --delete \
  --exclude='target' \
  --exclude='node_modules' \
  --exclude='dist' \
  --exclude='.git' \
  --exclude='catalog-info.yaml' \
  --exclude='README.md' \
  "${SOURCE}/" "${TARGET}/"

echo "Synced ${SOURCE} -> ${TARGET} (catalog-info.yaml and README.md kept as templates)"
