# ciot-oil-detection-project

50.046 Cloud &amp; IoT Project - Fall 2025

> [!NOTE]
>
> Ensure you have the following installed:
>
> - `aws-cli`
> - `opentofu`

## Architecture Diagram

![architectural-diagram](./assets/images/ciot-architecture-diagram.png)

## Setup Procedure

> [!NOTE]
>
> Remember to enter the commands when in repo directory so that `opentofu` can initialize.

Run the following commands to set up infra:

- `tofu init`
- `make validate plan`
- `tofu apply`

Run the following commands to tear down:

- `tofu plan -destroy`
- `tofu destroy`
