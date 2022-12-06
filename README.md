# docker-ce-atlantis
<<<<<<< Updated upstream
Container: run-atlantis/atlantis
=======

Lightweight Docker image for CE usage

Based on [runatlantis/atlantis](https://github.com/runatlantis/atlantis).

## Info

__Rio configuration file is source of truth, aka image configuration, values, etc.. are parameterized into [rio.yaml](./rio.yaml)__

## Build Status

| Pipeline | Last Pipeline status | Artifacts
| -------- | ----- | -------  
| `main-publish` | [![loading...][2]][1] | [Artifacts files](https://artifacts.apple.com/docker-apple/apay-docker/ce/atlantis/)


[1]: https://rio.apple.com/projects/applepay--docker-ce-atlantis
[2]: https://badges.pie.apple.com/badges/rio?p=applepay-docker-ce-atlantis&s=applepay-docker-ce-atlantis-main-publish
## Local usage
### Pull

By default `latest` image will be pulled. Ohters version are available as well (See above).

```sh
$ docker pull docker.apple.com/apay-docker/ce/atlantis:latest
```

Also possible to look at the [artficats repo](https://artifacts.apple.com/docker-apple/apay-docker/ce/atlantis/) and look for a specific version to pull. Image versioning matching to Rio (successfully completed) build.

```sh
# A specific Stable version
$ docker pull docker.apple.com/apay-docker/ce/atlantis:1.0.0

```
>>>>>>> Stashed changes
