# Releasing

1. Start PostgreSQL and MySQL with
   `docker compose up -d --wait postgres mysql`.
2. Run `bundle exec rake`, then run the specs under every Appraisal:
   `rails-7.1`, `rails-7.2`, `rails-8.0`, and `rails-main`.
3. Run the MySQL-tagged specs once with `MYSQL_ADAPTER=mysql2` and once with
   `MYSQL_ADAPTER=trilogy`.
4. Confirm the supported Ruby/Rails matrix and Rails main signal in CI.
5. Review the version in
   `lib/poollint/version.rb`.
6. Build and inspect the package with `bundle exec rake build` and
   `gem specification pkg/poollint-X.Y.Z.gem files`.
7. Install the built package into an isolated directory and verify
   `require "poollint"`.
8. Commit the version, create an annotated `vX.Y.Z` tag, and push
   the commit and tag.
9. Publish with MFA using `gem push pkg/poollint-X.Y.Z.gem`.

Publishing is intentionally a separate authenticated action. Do not publish
from an unreviewed working tree.
