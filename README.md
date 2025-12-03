# Origami Build System

This repository contains the GitLab CI/CD configuration used to build the Origami base image, Nvidia variant, and dedicated test image.

## Branch-specific pipelines

To keep test-image builds isolated from the base and Nvidia pipelines, use a dedicated branch named `test`:

1. Push commits that should exercise only the test image to the `test` branch (or fast-forward it to the desired commit).
2. The root pipeline on `test` runs only the test trigger (`trigger-test`). Base and Nvidia trigger jobs explicitly skip this branch so they continue running on their usual refs without interruption.
3. On other branches (for example, `main`), the base and Nvidia pipelines proceed as before, while test builds remain idle unless changes are mirrored to `test`.

This setup ensures:
- Base and Nvidia builds cancel only each other when new commits land on their ref.
- Multiple test runs cancel only previous test runs on `test`, without affecting the production pipelines.
