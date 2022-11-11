## Intro
This simply creates a single azure VM for a self-hosted github action runner, which provides somewhat similar performance to the default github-hosted runners. You can modify the VM size to suit your needs, or use cluster based solutions with [autoscaling](https://docs.github.com/en/actions/hosting-your-own-runners/autoscaling-with-self-hosted-runners#recommended-autoscaling-solutions).


## Usage
1. Follow the steps [here](https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners#adding-a-self-hosted-runner-to-an-organization), select Linux/x64 as the OS.
2. Copy the runner script from the `Download` section and replace it in `locals.custom_data` in `main.tf`, e.g. `https://github.com/actions/runner/releases/download/v2.299.1/actions-runner-linux-x64-2.299.1.tar.gz`
3. Copy the token from the `Configuration` section
4. Deploy:
    ```bash
    terraform init

    terraform apply -var="registration_token=<token_from_step_3>"
    
    ```
5. The deployed VM will be restarted after the runner is installed. After the restart, it should be available in `Actions > Runners` in your repository or organization settings.
6. Use the label `self-hosted` to run jobs on the self-hosted runner: `runs-on: self-hosted`