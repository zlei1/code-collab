[!NOTE]
> This project was completed through **Vibe Coding**

---

# code-collab

A high-performance, real-time collaborative code editor for pair programming, interviews, and remote teams. Built on the modern Rails 8 stack.

![Hero Screenshot](docs/assets/editor_main_1770194693854.png)

## Features

- **Real-Time Collaboration** — Distributed Operational Transformation (OT) for conflict-free concurrent editing.
- **Integrated File Explorer** — Browse and manage project structures within the virtual workspace.
- **On-the-Fly Code Execution** — Run Ruby scripts directly in the browser and see real-time output.
- **WebRTC Video & Chat** — Seamless communication with built-in video streaming and instant messaging.
- **Secure Workspaces** — Password-protected rooms and secure user isolation.
- **Premium UI/UX** — A dark-mode first, glassmorphic design built for developers.

## Gallery

<p align="center">
  <img src="docs/assets/room_list_1770194672084.png" width="45%" alt="Room Dashboard" />
  <img src="docs/assets/editor_run_output_1770194750187.png" width="45%" alt="Execution Output" />
</p>

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Rails 8.1 (Ruby 3.4) |
| Frontend | Hotwire (Turbo & Stimulus), Vanilla CSS, Lucide Icons |
| Real-time | ActionCable (WebSockets), Redis for OT session state |
| Communication | WebRTC for peer-to-peer video/audio |
| Deployment | Docker, Kamal, Thruster |

## Getting Started

### Prerequisites

- Ruby 3.4.x
- Redis
- SQLite3
- Docker (required for code execution environments)

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/your-org/code-collab.git
   cd code-collab
   ```

2. **Install dependencies**

   ```bash
   bundle install
   ```

3. **Setup database**

   ```bash
   bin/rails db:prepare
   ```

4. **Pull required Docker images**

   ```bash
   docker pull node:20-alpine
   docker pull python:3.12-alpine
   docker pull ruby:3.3-alpine
   ```

5. **Start the application**

   ```bash
   bin/dev
   ```

   Visit `http://localhost:3000`.

## Development

```bash
# Run tests
bin/rails test

# Linting
bin/rubocop

# Security scan
bin/brakeman
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes following [Conventional Commits](https://www.conventionalcommits.org/)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

Ensure `bin/ci` passes before requesting review.

## License

This project is available under the [MIT License](LICENSE).
