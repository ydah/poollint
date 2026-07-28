# Releasing

1. Run the complete command list in `README.md`.
2. Confirm the Rails matrix and Rails main signal in CI.
3. Review the version in
   `lib/poollint/version.rb`.
4. Build and inspect the package with `bundle exec rake build` and
   `gem contents --show-install-dir poollint`.
5. Commit the version, create an annotated `vX.Y.Z` tag, and push
   the commit and tag.
6. Publish with MFA using `gem push pkg/poollint-X.Y.Z.gem`.

Publishing is intentionally a separate authenticated action. Do not publish
from an unreviewed working tree.
