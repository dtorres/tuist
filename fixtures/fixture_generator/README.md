# Fixture Generator

A tool to generate large fixtures for the purposes of stress testing Tuist,

# Usage

```sh
swift run FixtureGenerator --projects 10 --targets 10 --sources 500
```

Options:

- `projects`: Number of projects to generate
- `targets`: Number of targets to generate
- `sources`: Number of sources to generate

# Features

- [x] Control number of projects
- [x] Control number of targets
- [x] Control number of sources
- [ ] Add pre-compiled libraries
- [ ] Add pre-compiled frameworks
- [ ] Add pre-compiled xcframeworks