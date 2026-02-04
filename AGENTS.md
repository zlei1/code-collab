# Repository Guidelines

## Project Structure & Module Organization
- `app/`: Rails application code (models, controllers, views, jobs, mailers).
- `config/`: environment settings, routes, initializers.
- `db/`: migrations, schema, and seeds.
- `test/`: Minitest suite (models, controllers, integration, etc.).
- `public/`, `storage/`, `tmp/`, `log/`: runtime assets and artifacts.
- `bin/`: project scripts (e.g., `bin/rails`, `bin/dev`, `bin/ci`).

## Build, Test, and Development Commands
- `bin/setup`: install dependencies, set up the database, and prepare the app.
- `bin/dev`: run the Rails server locally.
- `bin/rails db:migrate`: apply database migrations.
- `bin/rails test`: run the Minitest suite.
- `bin/rails test:system`: run system tests (optional).
- `bin/rubocop`: lint Ruby with `rubocop-rails-omakase`.
- `bin/brakeman`: static security scan for Rails.
- `bin/bundler-audit`: audit gems for known vulnerabilities.
- `bin/importmap audit`: check JS dependency vulnerabilities.
- `bin/ci`: run the full CI workflow (setup, lint, security, tests, seeds).

## Coding Style & Naming Conventions
- Ruby style follows `rubocop-rails-omakase` (`.rubocop.yml`).
- Indentation: 2 spaces; no tabs.
- Naming: `snake_case` for methods/files/variables, `CamelCase` for classes/modules.
- Rails conventions apply (e.g., singular model `User`, plural table `users`).

## Testing Guidelines
- Framework: Minitest (`test/` directory).
- Test files follow Rails defaults, e.g. `test/models/user_test.rb`.
- Run focused tests with `bin/rails test test/models/user_test.rb`.

## Commit & Pull Request Guidelines
- Commit messages use Conventional Commits, e.g. `feat: add reconnect banner` or `fix: handle nil user` (see `git log`).
- PRs should include a clear description, linked issues (if any), and screenshots for UI changes.
- Ensure `bin/ci` passes before requesting review.

## Security & Configuration Tips
- Use `bin/brakeman` and `bin/bundler-audit` before release.
- Prefer `bin/setup` over manual steps to keep environments consistent.
